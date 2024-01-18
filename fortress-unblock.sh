#!/bin/bash
config=/etc/fortress/fortress.conf

if [[ ! -f $config ]]; then
	echo "Missing configuration file: $config"
	exit
fi
redirect_ip=$(awk -F= '/redirect_ip/ && $1 !~ /^\s*#/ {print $2}' $config)
block_type=$( awk -F= '/block_type/  && $1 !~ /^\s*#/ {print $2}' $config)

ip=''
comment=''

if [[ $# -eq 0 ]]; then
	echo "Usage: $0 IP [comment]"
	exit
fi

if [[ ! $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "Error: invalid IP format"
	exit
fi

# Parameters:
# 1 - IP
# 2 - Comment
ipset_unblock() {
	ip=$1
	shift
	ipset_name=$( awk -F= '/ipset_name/  && $1 !~ /^\s*#/ {print $2}' $config)
	if [[ -z $ipset_name ]]; then
		echo -e "Error: unable to find ipset_name in $config.\nPlease check the configuration and try again.\n"
		exit
	fi
	ipset del $ipset_name $ip 2>/dev/null
}

# Parameters:
# 1 - IP
# 2 - Comment
iptables_unblock() {
	ip=$1
	shift
	chain=INPUT
	chain_name=$( awk -F= '/chain_name/  && $1 !~ /^\s*#/ {print $2}' $config)
	if [[ -n $chain_name ]]; then
		chain=$chain_name
	fi
	if [[ -n $1 ]]; then
		iptables -D $chain -j DROP -s $ip -m comment --comment "$*"
	else
		iptables -D $chain -j DROP -s $ip
	fi
}

# Parameters:
# 1 - IP
redirection() {
	if [[ -z $redirect_ip ]]; then
		echo "No redirect IP defined. Quiting without redirection."
		exit 1
	fi
	iptables -t nat -D PREROUTING -j DNAT -s $1 -p tcp --dport 80  --to $redirect_ip
	iptables -t nat -D PREROUTING -j DNAT -s $1 -p tcp --dport 443 --to $redirect_ip
	iptables -t nat -D PREROUTING -j DNAT -s $1 -p udp --dport 443 --to $redirect_ip
}

case "$block_type" in
	ipset)
		ipset_unblock $*
	;;
	iptables)
		iptables_unblock $*
	;;
	redirect)
		redirection $*
	;;
	*)
		echo "Error: unsupported block type in the configuration $config"
	;;
esac
