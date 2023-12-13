# About

Fortress is a simple tool aimed at reducing the manual sysadmin work involved in blocking attacking IPs.

The default thing that sysadmins do is `netstat -ntp`/`ss -ntp` to find what IPs are accessing the system and then blocking them. This tool does the same thing but costing significantly less resources and running the analysis for the sysadmin. 

This is a standalone daemon or a systemd service. 

The daemon supports excluding/whitelisting individual IPs and/or IP ranges(CIDR) in separate files. The good thing is that the whitelisting mechanism is pretty efficient, so it can take huge IP lists, like the IP ranges of google, yahoo or bing. 

To that end, we have provided a compiled list of IP ranges from the biggest providers on the net in the excludes folder.


Right now, the tool supports only TCP with UDP to be added soon. It checks conns only in either SYN_RECV or ESTABLISHED states to prevent either resource exhaustion or service interruption(flood).

# Configuration
Configuration, by default is expected to be in `/etc/fortress/fortress.conf`. We have tried to provide enough comments in there to reduce the need for separate documentation.

# Credits:
 - block icon, originally pulled from https://www.pngwing.com/en/free-png-mqxsx and resized
