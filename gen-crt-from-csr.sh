#!/bin/bash
#
# Script to create key and SAN certificate (crt) files.
# Version 20250618-001
#
# Usage is with or without a single argument - the csr filename 
#   If name is not provided on cmmand line, then it will be prompted for
#

# CA SPECIFIC PARAMETERS
CA_KEY='/root/myCA/intermediateCA/private/intermediate.key.pem'
CA_CHAIN='/root/myCA/intermediateCA/certs/intermediate.chain.pem'
CA_CRT='/root/myCA/intermediateCA/certs/intermediate.cert.pem'
VALIDITY_DAYS=365

echo "CA PARAMETERS SET"

# SERVER SPECIFIC PARAMETERS
SERVER_CSR=""
SERVER_CRT=""
SERVER_CFG=""
SERVER_CHAIN=""

# REQUEST Certificate Servce Request file
while  ! test -f "${SERVER_CSR}"  ; do read -p "Enter name of csr file : " SERVER_CSR ; done

echo "CSR FILE IS $SERVER_CSR"

# EXTRACT BASED OF FILENAME
BASE=`echo $SERVER_CSR | rev | cut -d. -f2 | rev | cut -d/ -f2`

echo "BASE NAME = $BASE"

# CREATE FILE NAMES FOR WORKING FILES
SERVER_CRT="$BASE.crt"
SERVER_CFG="$BASE.cfg"
SERVER_CHAIN="$BASE.chain"

# Copy CA Chain to Server Chain
sudo cp "$CA_CHAIN" "$SERVER_CHAIN"

# Extract common name (CN) from csr file
CN=`openssl req -in "${SERVER_CSR}" -text -noout | grep 'Subject:' | awk -F 'CN = ' '{print $2}' | awk -F ', ' '{print $1}'`
echo "Common Name: $CN"

# EXTRACT SAN DATA FROM THE CSR FILE
echo "--- Extracting SAN data from CSR file... ---"
input_string=$(openssl req -in "${SERVER_CSR}" -text -noout | grep 'X509v3 Subject Alternative Name:' -A 1 | tail -n 1 | sed 's/^[[:space:]]*//')
SAN_ENTRIES="${input_string/Address/}"

# CHECK if CSR file includes SAN attributes (terminate if none)
if [ "${SAN_ENTRIES}" == "" ] ; then echo "CSR request does not include SAN attributes. Terminating Script" ; exit ; fi

echo "CSF FILE = $SERVER_CSR"
echo "CFG FILE = $SERVER_CFG"
echo "CHAIN FILE = $SERVER_CHAIN"
echo "CN = $CN"
echo "SAN ENTRIES = $SAN_ENTRIES"


# CREATE CONFIG FILE FOR SERVICING CSR
cat <<EOF > "${SERVER_CFG}"
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C   = US
ST  = Arizona
L   = Tombstone
O   = Local
OU  = NA
CN  = $CN

[v3_req]
subjectAltName = "${SAN_ENTRIES}"
EOF

echo ""
echo "CONFIG FILE TO BE USED FOR CERTIFICATE CREATION IS LISTED BELOW"
echo ""
cat "${SERVER_CFG}"
echo ""

# GENERATE AND VERIFY SERVER SAN CERTIFICATE

echo "--- Generating Server Certificate (server.pem) ---"
openssl x509 -req -days ${VALIDITY_DAYS} \
    -in "${SERVER_CSR}" \
    -CA "${CA_CRT}" \
    -CAkey "${CA_KEY}" \
    -CAcreateserial \
    -out "${SERVER_CRT}" \
    -extensions v3_req \
    -extfile "${SERVER_CFG}"

echo ""
echo "Output certificate - check to ensure SAN entries are correct"
echo ""
openssl x509 -in "${SERVER_CRT}" -text -noout
echo ""
echo "Files associated with this request"
ls -la $BASE*


