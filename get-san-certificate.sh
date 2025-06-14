#!/bin/bash


# BELOW SHOULD BE EDITED TO MEET YOUR NEEDS

echo '
# server_cert.cnf
[req]
distinguished_name = req_distinguished_name
req_extensions = req_ext
prompt = no

[req_distinguished_name]
C   = US
ST  = Arizona
L   = Tombstone
O   = BITS Corp
OU  = Consulting
CN  = server.local

[req_ext]
subjectAltName = @alt_names

[alt_names]
IP.1 = 10.5.5.67
IP.2 = 10.5.5.68
DNS.1 = servera.local
DNS.2 = serverb.local
' > ./server_cert.cnf


echo "GENERATE CSR"
openssl req -new -key server.key -out server.csr -config ./server_cert.cnf

echo "VERIFY SAN ADDED TO CSR"
openssl req -noout -text -in server.csr | grep -A 1 "Subject Alternative Name"
# SAMPLE OUTPUT
#            X509v3 Subject Alternative Name:
#                IP Address:10.10.10.13, IP Address:10.10.10.14, IP Address:10.10.10.17, DNS:centos8-2.example.com, DNS:centos8-3.example.com


echo "GENERATE SAN CERTIFICATE named server1.crt"
openssl x509 -req -days 365 -in server.csr -CA /root/tls/certs/cacert.pem -CAkey /root/tls/private/cakey.pem -CAcreateserial -out server1.crt
# SAMPLE OUTPUT
# Signature ok
# subject=C = IN, ST = Karnataka, L = Bengaluru, O = GoLinuxCloud, OU = R&D, CN = ban21.example.com
# Getting CA Private Key

echo "VERIFY server1.crt SAN CERTIFICATE"
openssl x509 -text -noout -in server1.crt | grep -A 1 "Subject Alternative Name"


echo "GENERATE SAN CERTIFICATE USING -extensions OPTION names server2.crt"
openssl x509 -req -days 365 -in server.csr -CA /root/tls/certs/cacert.pem -CAkey /root/tls/private/cakey.pem -CAcreateserial -out server2.crt -extensions req_ext -extfile server_cert.cnf
# SAMPLE OUTPUT
# Signature ok
# subject=C = IN, ST = Karnataka, L = Bengaluru, O = GoLinuxCloud, OU = R&D, CN = ban21.example.com
# Getting CA Private Key

echo "VERIFY server2.crt SAN CERTIFICATE"
openssl x509 -text -noout -in server2.crt | grep -A 1 "Subject Alternative Name"                            
# SAMPLE OUTPUT
# X509v3 Subject Alternative Name:
#                 IP Address:10.10.10.13, IP Address:10.10.10.14, IP Address:10.10.10.17, DNS:centos8-2.example.com, DNS:centos8-3.example.com



