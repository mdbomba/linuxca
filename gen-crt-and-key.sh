#!/bin/bash

read -p 'Enter Country (e.g. US): ' C
read -p 'Enter Organization (e.g. Company): ' O
read -p 'Enter Organizational Unit (e.g. Department): ' OU
read -p 'Enter Common Name (e.g. www.company.com): ' CN1
read -p 'Enter Alternate Name (e.g. finance.company.com): ' CN2
read -p 'Enter IP Address (e.g. 10.0.0.100): ' IP1
read -p 'Enter Alternate IP Address: ' IP2

echo "
[v3_req]
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $CN1 
DNS.2 = $CN2
IP.1 = $IP1
IP.2 = $IP2
" > $CN1.cnf




openssl req -newkey rsa:2048 -nodes -keyout $CN1.key -out $CN1.csr -subj "/CN=$CN1/OU=$OU/O=$O/C=$C"

openssl x509 -req -in $CN1.csr -CA ica.crt -CAkey ica.key -CAcreateserial -out $CN1.crt -days 365 -sha256 -extfile $CN1.cnf -extensions v3_req

openssl verify -CAfile ica.chain $CN1.crt

openssl rsa -in $CN1.key -check -noout

openssl x509 -in $CN1.crt -text -noout

echo "Files created are listed below"

ls -la $CN1.*


