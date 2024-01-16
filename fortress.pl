#!/usr/bin/perl
use strict;
use warnings;
use POSIX qw(strftime setsid);
use Net::Patricia;
use Storable;

my $VERSION = '3.0';
my %established = ();
my %syn_sent = ();
my %ports = ();
my %blocked = ();
my $blocked_ref = \%blocked;
my $counter = 0;
my $old_pid = '';
my $umask = umask;
my %config = ();
my $config_path = '/etc/fortress/fortress.conf';
my $excludes = new Net::Patricia;
my $load = 0;

open my $conf_file, '<', $config_path or die "Error: Cannot open configuration file($config_path): $!";
# Read the configuration file, by skipping all lines that start with # and remove any quotes
while (my $line = <$conf_file>) {
    next if ($line !~ /^\s*\w/);
    $line =~ s/[\s\r\n]*$//g;
    $line =~ s/['"]*$//g;
    my ($key, $val) = split /=/, $line, 2; 
    $config{$key} = $val;
}
close $conf_file;

open my $LOG, '>>', $config{'log_file'} or die "Error: Unable to open logfile: $!\n";
select((select($LOG), $| = 1)[0]);

sub logger {
	my $conf_ref = shift;
	my $msg = shift;
	if ($conf_ref->{'debug'}) {
		print strftime('%b %d %H:%M:%S', localtime(time)) . " $msg\n";
	}
	print $LOG strftime('%b %d %H:%M:%S', localtime(time)) . " $msg\n";
}

sub get_load {
	my $conf_ref = shift;
	open my $load_file, '<', '/proc/loadavg' or logger($conf_ref, "Unable to open /proc/loadavg: $!");
	my @loadavg = split /\s+/, <$load_file>;
	close $load_file;
	return $loadavg[0];
}

sub clean_ips {
	my $conf_ref = shift;
	my $blocked_ref = shift;
	my $now = time()-$conf_ref->{'block_time'};
	return if (!exists $conf_ref->{'unblock_script'} or ! -x $conf_ref->{'unblock_script'});

	while (my ($ip, $btime) = each(%{$blocked_ref})) {
		if ($btime < $now) {
			logger($conf_ref, "Removing redirect for IP $ip");
			system($conf_ref->{'unblock_script'}, $ip);
			delete($blocked_ref->{$ip});
		}
	}
}

sub block_ip {
	my $conf_ref = shift;
	my $blocked_ref = shift;
	my $ip = shift;
	my $msg = shift;
	return if (exists $blocked_ref->{$ip});	   # already blocked

	logger($conf_ref, $msg);
	
	$blocked_ref->{$ip}=time();
	system($conf_ref->{'block_script'}, $ip, $msg);
}

# Make sure localhost is not blocked
$excludes->add_string('127.0.0.1', 'local');
if (exists $config{'exclude_files'} and $config{'exclude_files'} ne '') {
	foreach my $file(split /\s+/, $config{'exclude_files'}) {
		open my $fh, '<', $file;
		if (!$fh) {
			logger(\%config, "Error: Unable to open exclude file $file: $!");
			die "Error: Unable to open exclude file $file: $!\n";
		}
		while(<$fh>) {
			next if ($_ !~ /^\s*\d{1,3}\.\d{1,3}\.\d{1,3}/);
			if ($_ =~ /\.$/) {
				$_ =~ s/\.$/.0\/24/;
			}
			if ($_ =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\s*$/) {
				$_ =~ s/$/.0\/24/;
			}
			$excludes->add_string($_, $file);
		}
		close $fh;
	}
}

if (!exists $config{'block_script'} or ! -x $config{'block_script'}) {
	die "Error: missing block_script or $config{'block_script'} not executable\n";
}

# check if the daemon is running
if ( -e $config{'pid_file'} ) {
	# get the old pid
	umask 077;
	open my $PIDFILE, '<', $config{'pid_file'} or die "Error: Can't open pid file(".$config{'pid_file'}."): $!\n";
	$old_pid = <$PIDFILE>;
	close $PIDFILE;
	umask($umask);
	# check if $old_pid is still running
	if ( $old_pid =~ /[0-9]+/ ) {
		if ( -d "/proc/$old_pid" ) {
			die "Error: Fortress is already running!\n";
		}
	} else {
		die "Error: Incorrect pid format!\n";
	}
}

if ( -f $config{'store_db'}) {
	$blocked_ref = retrieve($config{'store_db'});
	logger(\%config, "Loaded blocked IPs from the store_db file.");
	unlink($config{'store_db'});
	logger(\%config, "Removed old store_db file.");
}

umask 077;
if (!$config{'debug'}) {
	open STDIN,  '<',  '/dev/null' or die "Error: Cannot read stdin: $! \n";
	open STDOUT, '>>', '/dev/null' or die "Error: Cannot write to stdout: $! \n";
	open STDERR, '>>', $config{'log_file'} or die "Error: Cannot write to stderr: $! \n";
	if ($config{'daemonize'}) {
        defined(my $pid=fork) or die "Error: Cannot fork process: $! \n";
        exit if $pid;
        setsid or die "Error: Unable to setsid: $!\n";
	}
}
open my $PIDFILE, '>', $config{'pid_file'} or die "Error: Unable to open pidfile $config{'pidfile'}: $!\n";
print $PIDFILE $$;
close $PIDFILE;
umask($umask);

# Get the list of monitored ports or assign defaults
if (!exists($config{'ports'}) or $config{'ports'} eq '') {
	$config{'ports'} = '80 443';
}

# Convert the port numbers to hex and put them in a hash
%ports = map { sprintf('%04X', $_) => 1 } split /\s+/, $config{'ports'};

# This is used only to optimize the check in the loop later.
# This way we don't need to convert every hex port from the file to decimal.
my %monitored_states = (
	'01' => 'ESTABLISHED',
	'03' => 'SYN_RECV'
);

$0 = 'Fortress';
logger("$0 version $VERSION started");
while (1) {
	# Make sure we start the loop with empty values
	%established= ();
	%syn_sent = ();
	$counter++;
	# We use a counter here, instead of actual times as it is more efficient. The counter is not so suffisticated, as
	# the code, some times may not execute in less then 1sec. But we don't need high accuracy here.
	clean_ips(\%config, $blocked_ref)	if ($counter%10 == 0);	# execute every 10th time (10sec)
	$load = get_load(\%config)			if ($counter%5  == 0);	# get the current load every 5 seconds
	$counter=0  						if ($counter > 10000);	# reset the counter to prevent comparison of very high numbers
	store \%blocked, $config{'store_db'} if ($counter%120 == 0);# execute every 120th time (rufly every 120sec)

	my $conn_count = $config{'low_conns'};
	my $syn_count  = $config{'low_syn_recv_conns'};
	# We do this check here, otherwise we would need to do it in the loop, just before we check the $established count.
	if ($load > $config{'high_load'}) {
		$conn_count = $config{'high_conns'};
		$syn_count  = $config{'high_syn_recv_conns'};
	}

	# Collect the stats
	open my $tcp, '<', '/proc/net/tcp' or die "Error: Failed to open /proc/net/tcp: $!";
	while (<$tcp>) {
		#  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
		#   0: 00000000:0016 00000000:0000 0A 00000000:00000000 00:00000000 00000000	 0	  0 4250 1 f5d40000 299 0 0 2 -1
		next if ($_ !~ /^\s+[0-9]+:\s+([A-Z0-9]{8}):([A-Z0-9]{4})\s+([A-Z0-9]{8}):([A-Z0-9]{4})\s+([A-Z0-9]{2})\s.*/);
		my $local_hex_ip	= $1;
		my $local_hex_port	= $2;
		my $remote_hex_ip	= $3;
		my $remote_hex_port	= $4;
		my $state			= $5;

		# Do not check states other then ESTABLISHED and SYN_RECV
		next if (!exists $monitored_states{$state});
		# The IP is written in reverse byte order, in hex. This converts each two hex chars into a number and at the end returns the dotted IPv4 format, that is expected.
		my $ip = hex(substr($remote_hex_ip,6,2)) . '.' . hex(substr($remote_hex_ip,4,2)) . '.' . hex(substr($remote_hex_ip,2,2)) . '.' . hex(substr($remote_hex_ip,0,2));
		# Do not continue if the IP is in the excluded list
		next if ($excludes->match_string($ip));

		# States:
		#   01 - ESTABLISHED
		#   03 - SYN_RECV
		#   06 - TIME_WAIT
		#   08 - CLOSE_WAIT

		# This is to catch smaller SYN flood attacks, usually dispersed between multiple source IPs.
		# This should be checked no matter the load value.
		if ($state eq '03') {
			$syn_sent{$ip}++;
		}

		# Check established conns, if the port is one of the ports configured to be monitored
		if ($state eq '01' and exists $ports{$local_hex_port}) {
			$established{$ip}++;
		}
	}	# read /proc/net/tcp

	# Check if we need to block any IP. We do it here and not in the above loop, so we know what was the actual number of conns from the IP.
	while (my ($ip, $conns) = each(%syn_sent)) {
		if ($syn_sent{$ip} > $config{'syn_recv_conns'}) {
			block_ip(\%config, $blocked_ref, $ip, "Blocking IP $ip for having more then $config{'syn_recv_conns'}($syn_sent{$ip}) SYN_RECV connections");
		}
	}
	while (my ($ip, $conns) = each(%established)) {
		if ($established{$ip} > $conn_count) {
			block_ip(\%config, $blocked_ref, $ip, "Blocking IP $ip for having more then $conn_count($established{$ip}) ESTABLISHED connections");
		}
	}
	close $tcp;
	select(undef, undef, undef, 1);
}
close $LOG;
