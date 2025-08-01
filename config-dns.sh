#!/bin/bash
# Script to create a /etc/hosts file
# V 20250616-002

# Define interface names and IPs
HN="invns"
DN="localnet"
IFACE1="ens33"  # WAN
IP="10.0.0.60"
IPCIDR="$IP/24"
GW1="10.0.0.2"
NS1="8.8.8.8"
NS2="8.8.4.4"
NPF='/etc/netplan/01-nameserver.yaml' # netplan config file
TS=`date +"%Y%m%d%H%M%S"`
echo "### PARAMETERS SET"

# Force Temp IP assignment (settings will be made permanent later in script)
sudo hostnamectl set-hostname "localhost"
sudo ip addr change $IPCIDR dev $IFACE1
sudo ip link set $IFACE1 up
sudo ip route flush default
sudo ip route add default via "$GW1"
sudo resolvectl dns "$IFACE1" "$NS1" "$NS2"
echo "### INTERFACE $IFACE1 SET TO  $IP  -  $GW1  -  $NS1  -  $NS2"
echo "### INITIAL BASIC CONFIGURATION SET"

# Ensure apt database is current
echo "### RUNNING apt update AND apt upgrade - PLEASE BE PATIENT"
sudo apt update 1>/dev/null 2>/dev/null
echo "### UPDATED APT DATABASE"
sudo apt upgrade -y 1>/dev/null 2>/dev/null
echo "### COMPLETED APT UPDATE AND UPGRADE"

# Disable cloud-init network management
sudo apt purge cloud-init -y 1>/dev/null 2>/dev/null
echo "### VERIFIED CLOUD-INIT HAS BEEN DISABLED"

# Enable current user to use sudo without security prompts
echo "$USER ALL=(ALL) NOPASSWD:ALL" |  sudo tee "/etc/sudoers.d/$USER" >/dev/null
sudo chown root:root "/etc/sudoers.d/$USER"
sudo chmod 440 "/etc/sudoers.d/$USER"
echo "### ADDED $USER TO SUDO NO PASSWORD LIST"

# Move existing netplan config files to /old/etc/netplan
sudo mkdir -p /old/etc/netplan
sudo mv -f /etc/netplan/* /old/etc/netplan/ 1>/dev/null 2>/dev/null
echo "### MOVED EXISTING NETPLAN CONFIG FILES TO /old/etc/netplan/"

# Create new netplan config file
echo " 
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE1:
      dhcp4: no
      addresses: [$IPCIDR]
      nameservers:
        addresses:
          - $NS1
          - $NS2
      routes:
        - to: 0.0.0.0/0
          via: $GW1
" | sudo tee $NPF >/dev/null
sudo chown root:root $NPF
sudo chmod 600 $NPF
echo "### CREATED NEW NETPLAN CONFIG FILE"

# Apply new network configuration
sudo netplan generate
sudo netplan apply
echo "### APPLIED NEW NETPLAN CONFIG FILE"

sudo hostnamectl set-hostname "$HN.$DN"

echo "127.0.0.1	localhost
127.0.1.1	`hostname -s`
# The following lines are desirable for IPv6 capable hosts
::1		ip6-localhost ip6-loopback
fe00::0		ip6-localnet
ff00::0		ip6-mcastprefix
ff02::1		ip6-allnodes
# BELOW ENTRIES ARE USED INSTEAD OF DNS REGISTRATION
10.0.0.1	HPEnvy
10.0.0.2	HPEnvy
10.0.0.3	dc
10.0.0.4	iis
10.0.0.11	ws1
10.0.0.21	invws1 invws1.localnet
10.0.0.22	invws2 invws2.localnet
10.0.0.23	invex1 invex1.localnet
10.0.0.31	invsv1 invsv1.localhost
10.0.0.32	invsv2 invsv2.localnet
10.0.0.50	invca invca.localnet
10.0.0.51	invrouter invrouter.localnet
10.0.0.41	invgw1 invgw1.localnet
10.0.0.42	invgw2 invgw2.localnet
" > ./hosts.new

# Update /etc/hosts file
sudo mv /etc/hosts /old/etc/hosts.$TS
sudo cp ./hosts.new /etc/hosts 
rm -f ./hosts.new
echo "### CREATED NEW /etc/hosts FILE"

# IMPLEMENT dnsmasq simple DNS service

sudo apt install dnsmasq -y
echo "### INSTALLED dnsmasq SIMPLE DNS SERVER (used /etc/hosts as its data source)"

sudo mv /etc/dnsmasq.conf /old/etc/dnsmasq.conf.$TS
echo "#/etc/dnsmasq.conf
#
# Listen on this specific port instead of the standard DNS port
# (53). Setting this to zero completely disables DNS function,
# leaving only DHCP and/or TFTP.
port=53
#
# If you don't want dnsmasq to read /etc/resolv.conf or any other
# file, getting its servers from this file instead (see below), then
# uncomment this.
no-resolv
#
# If you don't want dnsmasq to poll /etc/resolv.conf or other resolv
# files for changes and re-read them then uncomment this.
no-poll
#
# Add other name servers here, with domain specs if they are for
# non-public domains.
#server=/localnet/192.168.0.1
server=$NS1
server=$NS2
#
# If you want dnsmasq to listen for DHCP and DNS requests only on
# specified interfaces (and the loopback) give the name of the
# interface (eg eth0) here.
# Repeat the line for more than one interface.
interface=$IFACE1
#
# Or which to listen on by address (remember to include 127.0.0.1 if
# you use this.)
listen-address=127.0.0.1,$IP
#
# On systems which support it, dnsmasq binds the wildcard address,
# even when it is listening on only some interfaces. It then discards
# requests that it shouldn't reply to. This has the advantage of
# working even when interfaces come and go and change address. If you
# want dnsmasq to really bind only the interfaces it is listening on,
# uncomment this option. About the only time you may need this is when
# running another nameserver on the same machine.
#bind-interfaces
bind-interfaces
#
# Set this (and domain: see below) if you want to have a domain
# automatically added to simple names in a hosts-file.
#expand-hosts
expand-hosts
#
# Set the domain for dnsmasq. this is optional, but if it is set, it
# does the following things.
# 1) Allows DHCP hosts to have fully qualified domain names, as long
#     as the domain part matches this setting.
# 2) Sets the "domain" DHCP option thereby potentially setting the
#    domain of all systems configured by DHCP
# 3) Provides the domain part for "expand-hosts"
#domain=thekelleys.org.uk
domain=localnet
#
" | sudo tee /etc/dnsmasq.conf >/dev/null
echo "### CREATED NEW CONFIG FILE FOR dnsmasq DNS SERVER"

sudo service dnsmasq restart 
echo "### STARTED dnsmasq DNS SERVER"

sudo systemctl enable dnsmasq



