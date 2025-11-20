#!/bin/bash
#
# Script to create key and SAN certificate (crt) files.
# Version 20250618-001
#
# Usage is with or without a single argument - the csr filename 
#   If name is not provided on cmmand line, then it will be prompted for
#


# CA SPECIFIC FILE LOCATIONS
key='/root/myCA/intermediateCA/private/intermediate.key.pem'
chain='/root/myCA/intermediateCA/certs/intermediate.chain.pem'

if [ "$1" = "" ]; then csrfile='' ; else csrfile="$1" ; fi

# REQUEST Certificate Servce Request file
while  ! test -f "./$csrfile"  ; do read -p "Enter name of csr file : " csrfile  ; done

# CHECK if CSR file includes SAN attributes (terminate if none)
a='' ; a=`openssl req -noout -text -in $csrfile | grep -A 1 "Subject Alternative Name"`
if [ "$a" == "" ] ; then echo "CSR request does not include SAN attributes. Terminating Script" ; exit ; fi

# EXTRACT SAN attributes from CSR FILE
openssl req -noout -text -in $csrfile > workingset
# Read and parse DNS entries into an array
mapfile -t dns_entries < <(grep -oP 'DNS:\K[^,]+' "workingset")
# Read and parse IP addresses into an array
mapfile -t ip_addresses < <(grep -oP 'IP Address:\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "workingset")

# CREATE ALT NAMES SECTION FOR CERT CONFIG FILE
echo "[alt_names]" > x509san

if [ "$dns_entries" == "" ]; then echo "ERROR SAN Attributes must include at least one DNS entry. Aborting Script" ; exit ; fi
CN=${dns_entries[0]}


x=1
for dns in "${dns_entries[@]}"; do
  echo "DNS.$x = $dns"  >> x509san
  ((x++))
done

x=1
for ip in "${ip_addresses[@]}"; do
  echo "IP.$x = $ip"  >> x509san
  ((x++))
done

# CREATE CONFIG FILE FOR CERTIFICATE SERVICE REQUEST
echo "Generating config file for SAN certificates $CN.cfg"
echo "
# Config file for SAN certificates
[req]
distinguished_name = req_distinguished_name
req_extensions = req_ext
prompt = no

[req_distinguished_name]
C   = US
ST  = Arizona
L   = Tombstone
O   = Bomba Information Technology Services LLC
OU  = Consulting
CN  = $CN

[req_ext]
subjectAltName = @alt_names
" > $CN.cnf
cat x509san >> $CN.cnf

echo ""
echo "CONFIG FILE TO BE USED FOR CERTIFICATE CREATION IS LISTED BELOW"
echo ""
cat $CN.cnf
echo ""

# GENERATE AND VERIFY SERVER SAN CERTIFICATE
echo "Generating SAN Certificate $CN.crt"
openssl x509 -req -days 365 -in $CN.csr -CA "$chain" -CAkey "$key" -CAcreateserial -out $CN.crt -extensions req_ext -extfile $CN.cnf ; sleep 1
echo "Check $CN.crt for SAN attributes"
openssl x509 -text -noout -in $CN.crt | grep -A 1 "Subject Alternative Name"
echo "Verify Certificate - openssl verify -CAfile $chain $CN.crt"
openssl verify -CAfile $chain $CN.crt

rm x509san
rm $CN.cnf
cp $chain $CN.chain
















