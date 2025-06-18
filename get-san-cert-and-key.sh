#!/bin/bash
#
# Script to create key and SAN certificate (crt) files.
# Version 20250618-001


# EDITABLE PARAMETERS
IP1="10.5.5.69"
DNS1="server"
DNS2="server.localnet"
CN="server"

# CLEAR OUT OLD CERT GENERATION INFORMATION
rm -f $CN.*

# CA SPECIFIC FILE LOCATIONS
intkey='/root/myCA/intermediateCA/private/intermediate.key.pem'
intcert='/root/myCA/intermediateCA/certs/intermediate.cert.pem'
intchain='/root/myCA/intermediateCA/certs/intermediate.chain.pem'

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

[alt_names]
IP.1 = $IP1
DNS.1 = $DNS1
DNS.2 = $DNS2
" > $CN.cnf


# GENERATE PRIVATE KEY
echo "Generating private key $CN.key"
openssl genrsa -out $CN.key 4096 ; sleep 2

# GENERATE AND VERIFY SAN CERTIFICATE SERVICE REQUEST
echo "Generating SAN certificate service request $CN.csr" 
openssl req -new -key $CN.key -out $CN.csr -config $CN.cnf ; sleep 1
echo "Checking $CN.csr to ensure it includes SAN attributes"
openssl req -noout -text -in $CN.csr | grep -A 1 "Subject Alternative Name" ; sleep 1

$ GENERATE AND VERIFY SERVER SAN CERTIFICATE
echo "Generating SAN Certificate $CN.crt"
openssl x509 -req -days 365 -in $CN.csr -CA "$intchain" -CAkey "$intkey" -CAcreateserial -out $CN.crt -extensions req_ext -extfile $CN.cnf ; sleep 1
echo "Check $CN.crt for SAN attributes"
openssl x509 -text -noout -in $CN.crt | grep -A 1 "Subject Alternative Name"
echo "Verify Certificate - openssl verify -CAfile $intchain $CN.crt"
openssl verify -CAfile $intchain $CN.crt

















