Name:		fortress
Version:	1.0
Release:	2
Summary:	Fortress connection monitoring and protection
License:	GPLv2
URL:		https://github.com/hackman/Fortress
Source0:	%{name}-%{version}.tgz
BuildArch:	noarch
BuildRoot:	%(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)
Requires:	perl perl-Net-Patricia iptables iptables-services
Provides:	fortress
AutoReqProv: no

%description
This package provides the Fortress connection monitoring and
protection system.
It monitors TCP and UDP connections and automaticaly blocks
and unblocks IPs that may put the machine at risk.

%prep
%setup -q

%build

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}/etc/fortress
mkdir -p %{buildroot}/etc/systemd/system
mkdir -p %{buildroot}/etc/sudoers.d
mkdir -p %{buildroot}/usr/sbin
mkdir -p %{buildroot}/usr/share/fortress
mkdir -p %{buildroot}/usr/lib/fortress
mkdir -p %{buildroot}/var/log/fortress
mkdir -p %{buildroot}/var/run/fortress
mkdir -p %{buildroot}/var/cache/fortress
cp fortress.conf %{buildroot}/etc/fortress/
cp excludes/* %{buildroot}/etc/fortress/
cp fortress.service %{buildroot}/etc/systemd/system
cp fortress.pl %{buildroot}/usr/sbin/fortress
cp fortress-block.sh %{buildroot}/usr/sbin/fortress-block
cp fortress-unblock.sh %{buildroot}/usr/sbin/fortress-unblock
cp LICENSE %{buildroot}/usr/share/fortress

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root,-)
%config(noreplace)     /etc/fortress/fortress.conf
%config(noreplace)     /etc/fortress/cloudflare.txt
%config(noreplace)     /etc/fortress/google.txt
%config(noreplace)     /etc/fortress/yahoo.txt
%config(noreplace)     /etc/fortress/baidu.txt
%config(noreplace)     /etc/fortress/msnbot.txt
%config(noreplace)     /etc/fortress/bingbot.txt
%config(noreplace)     /etc/fortress/yandex.txt
%config(noreplace)     /etc/fortress/my.txt
#%config(noreplace)     /etc/systemd/system/fortress.service
#%attr(600, root, root) /etc/sudoers.d/fortress
#%attr(600, root, root) /etc/cron.d/fortress
%attr(750, root, root) /usr/lib/fortress
%attr(700, root, root) /usr/sbin/fortress
%attr(700, root, root) /usr/sbin/fortress-block
#%attr(700, root, root) /usr/sbin/fortress-unblock
%attr(750, root, root) /usr/share/fortress
%attr(644, root, root) /usr/share/fortress/LICENSE
%attr(750, root, root) /var/log/fortress
%attr(750, root, root) /var/run/fortress
%attr(700, root, root) /var/cache/fortress

%post
%systemd_post fortress.service

%preun
if [ -f /var/run/fortress.pid ]; then
	kill $(cat /var/run/fortress.pid)
fi

%postun
%systemd_postun_with_restart fortress.service

%posttrans
#%changelog
#%include ChangeLog.md
