#!/bin/bash

# Define variables for certificate details
COUNTRY="US"
STATE="Arizona"
LOCALITY="Tombstone" # Updated Locality
ORGANIZATION="Local"
ORGANIZATIONAL_UNIT="NA"
COMMON_NAME="chef360.local.lab" # The fully qualified domain name (FQDN)
EMAIL="admin@local.lab"
KEY_SIZE=2048
OUTPUT_DIR="./"

# Define Subject Alternative Names
SAN_DNS_1="chef360"
SAN_DNS_2="chef360.local.lab" 
SAN_IP_1="10.0.0.8"


# Define output file names
KEY_FILE="${OUTPUT_DIR}/chef360.key"
CSR_FILE="${OUTPUT_DIR}/chef360.csr"
CONFIG_FILE="${OUTPUT_DIR}/chef360.cnf"

# Ensure the output directory exists
mkdir -p "$OUTPUT_DIR"

echo "--- Generating OpenSSL configuration file ---"

# Create the configuration file with the SAN extensions
cat <<EOF > "${CONFIG_FILE}"
[req]
default_bits = ${KEY_SIZE}
encrypt_key = no
default_md = sha256
prompt = no
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]
C = ${COUNTRY}
ST = ${STATE}
L = ${LOCALITY}
O = ${ORGANIZATION}
OU = ${ORGANIZATIONAL_UNIT}
CN = ${COMMON_NAME}
emailAddress = ${EMAIL}

[v3_req]
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${SAN_DNS_1}
DNS.2 = ${SAN_DNS_2}
IP.1 = ${SAN_IP_1}
EOF

echo "--- Generating Private Key and CSR for ${COMMON_NAME} with SANs ---"

# Generate the private key and CSR using the config file
openssl req -new -keyout "${KEY_FILE}" -out "${CSR_FILE}" -config "${CONFIG_FILE}"

echo "--- Process Complete ---"
echo "Private Key saved to: ${KEY_FILE}"
echo "CSR saved to: ${CSR_FILE}"
echo "Config file saved to: ${CONFIG_FILE}"

# --- TEST OUTPUT / VERIFICATION STEP ---
echo "--- Verifying CSR details and SAN attributes (Test Output) ---"
openssl req -text -noout -verify -in "${CSR_FILE}"

if [ $? -eq 0 ]; then
    echo "CSR verification successful."
else
    echo "CSR verification failed."
fi

