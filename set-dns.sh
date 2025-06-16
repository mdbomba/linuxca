#!/bin/bash
# Script to install dnsmasq and have it use the /etc/hosts file as its database
# V 20250616-001

ip='10.5.5.60'

sudo apt -y install dnsmasq
sudo echo "
port=53
no-resolv
no-poll
server=8.8.8.8
server=8.8.4.4
interface=enp1s0
listen-address=127.0.0.1,$ip
bind-interfaces
expand-hosts
" >> /etc/dnsmasq.conf
sudo systemctl start dnsmasq
sudo systemctl restart dnsmasq
sudo systemctl status dnsmasq

