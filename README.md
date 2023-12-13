# About

Fortress is a simple tool aimed at reducing the manual sysadmin work involved in blocking attacking IPs.

The default thing that sysadmins do is `netstat -ntp`/`ss -ntp` to find what IPs are accessing the system, during overload times. These tools may be slow to produce the desired information and are usully combined with piping this information into grep/awk/sort/uniq additional tools to get the right data.

Fortress is able to identify such attacks in less then 1sec and then block the offending IPs. This tool does the same thing that a sysadmin would do, but costing significantly less resources and faster.

This is a standalone daemon or a systemd service. 

The daemon supports excluding/whitelisting individual IPs and/or IP ranges(CIDR) in separate files. The good thing is that the whitelisting mechanism is pretty efficient(based on Patricia Trie for the IP lookups), so it can take huge IP lists, like the IP ranges of google, cloudflare, bing or etc.

To that end, we have provided a compiled list of IP ranges from the biggest providers on the net in the excludes folder.


Right now, the tool supports only TCP with UDP to be added soon. It checks conns only in either SYN_RECV or ESTABLISHED states to prevent either resource exhaustion or service interruption(flood).

# How does it work?

Fortress parses `/proc/net/tcp`(the tcp states provided by the Linux kernel) every second and also checks the load of the machine from `/proc/loadavg`. 

It first creates a list of connections for the monitored ports. Then based on the configuration(high_load, low_conns, high_cons, syn_recv_conns) it decides if an IP has to be blocked. 

It uses an external [shell script](fortress-block.sh), that can be modified by the administrator, to block IPs.


With the default configuration, Fortress will look for syn flood conns all the time. These are IPs sending more then 20 TCP packets with SYN flag set. This means that at a single moment, this IP has tried to open more then 20(syn_recv_conns) simultaneous connections to the server. 
 
It will also check established connections. These are connections that already have the TCP 3-way handshake finished and application is expected to handle them. 
When the load is below the high limit(high_load), the number of simultaneous connections from a single IP has to be above 50(low_conns) in order to get blocked.
When the load is above the high limit(high_load), the number of simultaneous connections from a single IP has to be above 30(high_conns) in order to get blocked.

# Configuration
Configuration, by default is expected to be in `/etc/fortress/fortress.conf`. We have tried to provide enough comments in there to reduce the need for separate documentation.

# Blocking
Fortress supports 3 different types of blocking the offending IPs. And all 3 are defined in the `fortress-block.sh`.
1. `iptables` - blocking the IPs directly in your firewall with iptables. You can also create a dedicated chain for that and set its name in fortres.conf
2. `ipset` - a more efficient blocking mechanism would be to levarage IPsets. This allows you to block large number of IPs without overwhelming iptables and slowing down the packet processing.
3. redirection - in this mechanism, we forward the TCP connection to a separate server, on which we expect to have a block page explaining, why the client is not seeing the expected web page. This mechanims uses DNAT and SNAT to achieve this and is the most resource inefficient way. However, it does give proper information to the end user. An example blocked page can be seen in the [block_page](block_page) folder.

Feel free to modify this script in any way, to suit your blocking needs.

# Credits:
 - block icon, originally pulled from https://www.pngwing.com/en/free-png-mqxsx and resized
