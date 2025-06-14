#!/bin/bash

cd ~

mkdir -p ~/myCA/rootCA/{certs,crl,newcerts,private,csr}
mkdir -p ~/myCA/intermediateCA/{certs,crl,newcerts,private,csr}
echo 1000 > ~/myCA/rootCA/serial
echo 1000 > ~/myCA/intermediateCA/serial
echo 0100 > ~/myCA/rootCA/crlnumber 
echo 0100 > ~/myCA/intermediateCA/crlnumber
touch ~/myCA/rootCA/index.txt
touch ~/myCA/intermediateCA/index.txt

# ROOT CA KEY AND CERTIFICATE GENERATION

echo "GENERATE ROOT CA PRIVATE KEY"
openssl genrsa -out ~/myCA/rootCA/private/ca.key.pem 4096
chmod 400 ~/myCA/rootCA/private/ca.key.pem

echo "SHOW CONTENTS OF PRIVATE KEY"
openssl rsa -noout -text -in ~/myCA/rootCA/private/ca.key.pem

echo "GENERATE ROOT CA PUBLIC CERTIFICATE"
openssl req -config openssl_root.cnf -key ~/myCA/rootCA/private/ca.key.pem -new -x509 -days 7300 -sha256 -extensions v3_ca -out ~/myCA/rootCA/certs/ca.cert.pem -subj "/C=US/ST=California/L=San Francisco/O=Example Corp/OU=IT Department/CN=Root CA"
chmod 444 ~/myCA/rootCA/certs/ca.cert.pem

echo "SHOW CONTENT OF ROOT PUBLIC CERTIFICATE"
openssl x509 -noout -text -in ~/myCA/rootCA/certs/ca.cert.pem

# INTERMEDIATE CA KEY AND CERTIFICATE GENERATION

echo "GENERATE INTERMEDIATE CA PRIVATE KEY"
openssl genrsa -out ~/myCA/intermediateCA/private/intermediate.key.pem 4096
chmod 400 ~/myCA/intermediateCA/private/intermediate.key.pem

echo "GENERATE CSR TO REQUEST INTERMEDIATE CA PUBLIC CERTIFICATE"
openssl req -config openssl_intermediate.cnf -key ~/myCA/intermediateCA/private/intermediate.key.pem -new -sha256 -out ~/myCA/intermediateCA/certs/intermediate.csr.pem -subj "/C=US/ST=California/L=San Francisco/O=Example Corp/OU=IT Department/CN=Intermediate CA"

echo "REQUEST INTERMEDIATE CA PUBLIC CERTIFICATE USING CSR FILE"
openssl ca -config openssl_root.cnf -extensions v3_intermediate_ca -days 3650 -notext -md sha256 -in ~/myCA/intermediateCA/certs/intermediate.csr.pem -out ~/myCA/intermediateCA/certs/intermediate.cert.pem
chmod 444 ~/myCA/intermediateCA/certs/intermediate.cert.pem

echo "VERIFY CERTIFICATE FILE IS NOW LOCATED IN THE CA INDEX FILE"
cat ~/myCA/rootCA/index.txt
# SHOULD RETURN A LINE INCLUDING
# V 330503082700Z 1000 unknown /C=US/ST=California/O=Example Corp/OU=IT Department/CN=Intermediate CA

echo "SHOW CONTENT OF INTERMEDIATE CA PUBLIC CERTIFICATE"
openssl x509 -noout -text -in ~/myCA/intermediateCA/certs/intermediate.cert.pem

echo "USE OPENSSL VERIFY PROCESS TO VERIFY INTERMEDIATE CERTIFICATE"
openssl verify -CAfile ~/myCA/rootCA/certs/ca.cert.pem ~/myCA/intermediateCA/certs/intermediate.cert.pem

# CREATE TRUST CHAIN CERTIFICATE

echo "CHREATE TRUST CHAIN FILE"
cat ~/myCA/intermediateCA/certs/intermediate.cert.pem ~/myCA/rootCA/certs/ca.cert.pem > ~/myCA/intermediateCA/certs/ca-chain.cert.pem

echo "USING OPENSSL VERIFY TO CHECK CHAIN FILE"
openssl verify -CAfile ~/myCA/intermediateCA/certs/ca-chain.cert.pem ~/myCA/intermediateCA/certs/intermediate.cert.pem

# CREATE SAMPLE WEB SERVER CERT TO VERIFY OVERALL CA FUNCTIONALITY

echo "CREATE COMMON ATTRIBUTES IN openssl.cnf FILE"



echo "GENERATE WEB SERVER PRIVATE KEY"
openssl genpkey -algorithm RSA -out ~/myCA/intermediateCA/private/www.example.com.key.pem
chmod 400 ~/myCA/intermediateCA/private/www.example.com.key.pem

echo "CREATE WEB SERVER CERTIFICATE REQUEST (CSR)"
openssl req -config ~/myCA/openssl_intermediate.cnf -key ~/myCA/intermediateCA/private/www.example.com.key.pem -new -sha256 -out ~/myCA/intermediateCA/csr/www.example.com.csr.pem

echo "REQUEST WEB SERVER CERT USING CSR FILE"
openssl req -config ~/myCA/openssl_intermediate.cnf -key ~/myCA/intermediateCA/private/www.example.com.key.pem -new -sha256 -out ~/myCA/intermediateCA/csr/www.example.com.csr.pem -batch

echo "SIGN WEB SERVER PUBLIC CERT USING INTERMEDIATE CERT"
openssl ca -config ~/myCA/openssl_intermediate.cnf -extensions server_cert -days 375 -notext -md sha256 -in ~/myCA/intermediateCA/csr/www.example.com.csr.pem -out ~/myCA/intermediateCA/certs/www.example.com.cert.pem


echo "VERIFY NEW SERVER CERTIFICATE"
openssl x509 -noout -text -in ~/myCA/intermediateCA/certs/www.example.com.cert.pem




