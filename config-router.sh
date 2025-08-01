#!/bin/bash
# name - config-linux-router
# Script to setup a linux server as a 3 port router
# V 20250706-001

# Define interface names and IPs
HN="invrouter"
DN="localnet"
IFACE1="ens33"  # WAN
IFACE2="ens34"  # LAN1
IFACE3="ens35"  # LAN2
IP1="10.0.0.51/24"
GW1="10.0.0.2"
IP2="10.0.1.1/24"
IP3="10.0.2.1/24"
NS1="10.0.0.60"
NS2="8.8.8.8"
DFN='/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg'  # cloud-init disablement file
NPF='/etc/netplan/99-router.yaml' # netplan config file
echo "### PARAMETERS SET"

# Force Temp IP assignment (settings will be made permanent later in script)
sudo hostnamectl set-hostname "localhost"
sudo ip addr change $IP1 dev $IFACE1
sudo ip link set $IFACE1 up
sudo ip route flush default
sudo ip route add default via "$GW1"
sudo resolvectl dns "$IFACE1" "$NS1" "$NS2"
echo "### INTERFACE $IFACE1 SET TO  $IP1  -  $GW1  -  $NS1  -  $NS2"
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
echo "$USER ALL=(ALL) NOPASSWD:ALL" |  sudo tee "/etc/sudoers.d/$USER" 1>/dev/null 2>/dev/null
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
      addresses: [$IP1]
      nameservers:
        addresses:
          - $NS1
          - $NS2
      routes:
        - to: 0.0.0.0/0
          via: $GW1
    $IFACE2:
      dhcp4: no
      addresses: [$IP2]
    $IFACE3:
      dhcp4: no
      addresses: [$IP3]
" | sudo tee $NPF 1>/dev/null 2>/dev/null
sudo chown root:root $NPF
sudo chmod 600 $NPF
echo "### CREATED NEW NETPLAN CONFIG FILE"

# Apply new network configuration
sudo netplan generate
sudo netplan apply
echo "### APPLIED NEW NETPLAN CONFIG FILE"

# Create a new /etc/hosts file
IP=${IP1%/*}
echo "127.0.0.1	localhost
127.0.1.1	$HN

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters

# The following lines were added during host configuration
$IP  $HN  $HN.$DN
" > ./hosts.temp
TS=`date +"%Y%m%d%H%M%S"`
sudo cp /etc/hosts /old/etc/hosts.$TS
sudo cp ./hosts.temp /etc/hosts
rm ./hosts.temp
echo "### CREATED NEW /etc/hosts TO ADD $IP  $HN  $HN.$DN"

# Set hostname
sudo hostnamectl set-hostname "$HN"
echo "### HOSTNAME SET TO $HN"

# Ensure openvswitch is installed
sudo apt install -y openvswitch-switch 1>/dev/null 2>/dev/null
echo "### COMPLETED OPENVSWITCH-SWITCH INSTALL CHECK"

# Ensure iptables-persistent is installed
sudo apt install -y iptables-persistent 1>/dev/null 2>/dev/null
echo "### COMPLETED IPTABLES-PERSISTENT INSTALL CHECK"

# Enable IP forwarding
grep -v "net.ipv4.ip_forward=1" /etc/sysctl.conf | sudo tee /etc/sysctl.conf >/dev/null
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf >/dev/null
sudo sysctl -p 1>/dev/null 2>/dev/null
echo "### COMPLETED IP FORWARDING ENABLED CHECK"

# Clear old configs
sudo ip route flush default 1>/dev/null 2>/dev/null
sudo iptables --flush 1>/dev/null 2>/dev/null
echo "### COMPLETED FLUSHING IPTABLES ROUTING TABLE"

# Set up routing rules
sudo ip route add default via $GW1 dev $IFACE1 1>/dev/null 2>/dev/null
# NAT for outbound traffic from LANs to WAN
sudo iptables -t nat -A POSTROUTING -o $IFACE1 -j MASQUERADE 1>/dev/null 2>/dev/null
# Allow forwarding between interfaces
sudo iptables -A FORWARD -i $IFACE2 -o $IFACE3 -j ACCEPT 1>/dev/null 2>/dev/null
sudo iptables -A FORWARD -i $IFACE3 -o $IFACE2 -j ACCEPT 1>/dev/null 2>/dev/null
sudo iptables -A FORWARD -i $IFACE2 -o $IFACE1 -j ACCEPT 1>/dev/null 2>/dev/null
sudo iptables -A FORWARD -i $IFACE3 -o $IFACE1 -j ACCEPT 1>/dev/null 2>/dev/null
sudo iptables -A FORWARD -i $IFACE1 -o $IFACE2 -m state --state RELATED,ESTABLISHED -j ACCEPT 1>/dev/null 2>/dev/null
sudo iptables -A FORWARD -i $IFACE1 -o $IFACE3 -m state --state RELATED,ESTABLISHED -j ACCEPT 1>/dev/null 2>/dev/null
# Save iptables rules
sudo netfilter-persistent save 1>/dev/null 2>/dev/null
echo "### COMPLETED ROUTING TABLE CINFIGURATION USING IPTABLES"


echo ""
echo "### SCRIPT COMPLETED ###"

