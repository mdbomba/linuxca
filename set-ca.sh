#!/bin/bash

# Script to create a linux certificate authority
# Version 20250616-02
#
# requires openssl_root.cnf and openssl_intermediate.cnf
#
# Function to read input with default value ( a = read_input {Prompt} {default} )
function read_input {
read -p "$1 [$2] = " i
if [ "$i" != '' ]; then echo $i; else echo $2; fi
}
# Function to verify we are running as root
function is-root {
if [ $EUID -ne 0 ]; then 
  echo "YOU NEED TO RUN THIS SCRIPT AS ROOT  (sudo)"
  echo "Press any key to exit script"
  read
  exit
else
  echo "SCRIPT RUNNING AS ROOT (ALL GOOD)"
fi
}

# Terminate if not running as root (sudo)
is-root

#########################
# CONFIGURABLE PARAMETERS
#########################

## Config Files
rootCACnf="/root/myCA/openssl_root.cnf"
intermediateCACnf="/root/myCA/openssl_intermediate.cnf"

## CERT SUBJECT INPUT
rootCASubject="/C=US/ST=Arizona/L=Tombstone/O=Bomba Information Technology Services LLC/OU=Consulting/CN=Root CA"
intermediateCASubject="/C=US/ST=Arizona/L=Tombstone/O=Bomba Information Technology Services LLC/OU=Consulting/CN=Intermediate CA"

## NAME OF PEM CERTIFICATE FILES
rootCACert="/root/myCA/rootCA/certs/ca.cert.pem"
intermediateCACert="/root/myCA/intermediateCA/certs/intermediate.cert.pem"

## NAME OF PEM KEY FILES
rootCAKey="/root/myCA/rootCA/private/ca.key.pem"
intermediateCAKey="/root/myCA/intermediateCA/private/intermediate.key.pem"

## NAME OF INTERMEDIATE CERTIFICATE CSR FILE
intermediateCACsr="/root/myCA/intermediateCA/csr/intermediate.csr"

## NAME OF INTERMEDIATE CA CHAIN FILE
intermediateCAChain="/root/myCA/intermediateCA/certs/intermediate.chain.pem"

#########################################################
# CREATE DIRECTORY STRUCTURE FOR root and intermediate CA
#########################################################
mkdir -p /root/myCA/rootCA/{certs,crl,newcerts,private,csr}
mkdir -p /root/myCA/intermediateCA/{certs,crl,newcerts,private,csr}
echo 1000 > /root/myCA/rootCA/serial
echo 1000 > /root/myCA/intermediateCA/serial
echo 0100 > /root/myCA/rootCA/crlnumber 
echo 0100 > /root/myCA/intermediateCA/crlnumber
touch /root/myCA/rootCA/index.txt
touch /root/myCA/intermediateCA/index.txt


cd /root/myCA


# GENERATE ROOT CA

echo "GENERATE ROOT CA PRIVATE KEY"
openssl genrsa -out "$rootCAKey" 4096
chmod 400 "$rootCAKey"

echo "SHOW CONTENTS OF PRIVATE KEY"
openssl rsa -noout -text -in "$rootCAKey"

echo "GENERATE ROOT CA PUBLIC CERTIFICATE"
openssl req -config openssl_root.cnf -key "$rootCAKey" -new -x509 -days 7300 -sha256 -extensions v3_ca -out "$rootCACert" -subj "$rootCASubject"
chmod 444 "$rootCACert"

echo "SHOW CONTENT OF ROOT PUBLIC CERTIFICATE"
openssl x509 -noout -text -in "$rootCACert"


# GENERATE INTERMEDIATE CA 

echo "GENERATE INTERMEDIATE CA PRIVATE KEY"
openssl genrsa -out "$intermediateCAKey" 4096
chmod 400 "$intermediateCAKey"

echo "GENERATE CSR TO REQUEST INTERMEDIATE CA PUBLIC CERTIFICATE"
openssl req -config openssl_intermediate.cnf -key "$intermediateCAKey" -new -sha256 -out "$intermediateCACsr" -subj "$intermediateCASubject"

echo "REQUEST INTERMEDIATE CA PUBLIC CERTIFICATE AND SIGN WITH ROOT KEY"
openssl ca -config openssl_root.cnf -extensions v3_intermediate_ca -days 3650 -notext -md sha256 -in "$intermediateCACsr" -out "$intermediateCACert"
chmod 444 "$intermediateCACert"

echo "VERIFY CERTIFICATE FILE IS NOW LOCATED IN THE CA INDEX FILE"
cat ~/myCA/rootCA/index.txt
# SHOULD RETURN A LINE INCLUDING
# V 330503082700Z 1000 unknown /C=US/ST=Arizona/L=Cochise/O=Bomba Information Technology Services LLC/OU=Consulting/CN=Intermediate CA

echo "SHOW CONTENT OF INTERMEDIATE CA PUBLIC CERTIFICATE"
openssl x509 -noout -text -in "$intermediateCACert"

echo "USE OPENSSL VERIFY PROCESS TO VERIFY INTERMEDIATE CERTIFICATE"
openssl verify -CAfile "$rootCACert" "$intermediateCACert"

# CREATE TRUST CHAIN CERTIFICATE

echo "CHREATE TRUST CHAIN FILE"
cat "$intermediateCACert" "$rootCACert" > "$intermediateCAChain"

echo "USING OPENSSL VERIFY TO CHECK CHAIN FILE"
openssl verify -CAfile "$intermediateCAChain" "$intermediateCACert"






