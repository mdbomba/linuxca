#!/bin/bash
# filename - gen-csr.sh
# version - 20250721-02
# description - Generates a private key and CSR with SAN support
# usage - sudo bash gen-csr.sh

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root."
    exit 1
fi

# --- Load or create vars file ---
VARS_FILE="/root/ca-vars.conf"

load_vars() {
    [ -f "$VARS_FILE" ] && source "$VARS_FILE"
}

prompt_var() {
    local var_name="$1"
    local prompt_msg="$2"
    local current_val="${!var_name}"
    if [ -z "$current_val" ]; then
        read -p "$prompt_msg" "$var_name"
    fi
}

save_vars() {
    cat > "$VARS_FILE" << EOF
# ca-vars.conf - Shared variables for CA scripts
# Edit these values or delete them to be prompted on next run

# CA hierarchy location
CA_DIR='${CA_DIR}'

# Certificate subject fields
C='${C}'
ST='${ST}'
L='${L}'
O='${O}'
OU='${OU}'
EOF
}

load_vars

prompt_var CA_DIR "Enter CA directory path [/root/myCA]: "
CA_DIR="${CA_DIR:-/root/myCA}"
prompt_var C "Enter Country Name (2 letter code): "
prompt_var ST "Enter State or Province Name: "
prompt_var L "Enter Locality Name: "
prompt_var O "Enter Organization Name: "
prompt_var OU "Enter Organizational Unit Name: "

# Server-specific prompts
prompt_var COMMON_NAME "Enter Common Name / FQDN (e.g. chef360.demo.lab): "
prompt_var SAN_DNS "Enter space-separated DNS names (e.g. chef360 chef360.demo.lab): "
prompt_var SAN_IP "Enter space-separated IP addresses (e.g. 10.0.0.50): "

save_vars

KEY_SIZE=2048

# Derive base name from CN
BASE_NAME=$(echo "$COMMON_NAME" | cut -d. -f1)
OUTPUT_DIR="."

KEY_FILE="${OUTPUT_DIR}/${BASE_NAME}.key"
CSR_FILE="${OUTPUT_DIR}/${BASE_NAME}.csr"
CONFIG_FILE="${OUTPUT_DIR}/${BASE_NAME}.cnf"

echo "--- Generating OpenSSL configuration file ---"

cat <<EOF > "${CONFIG_FILE}"
[req]
default_bits = ${KEY_SIZE}
encrypt_key = no
default_md = sha256
prompt = no
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]
C  = ${C}
ST = ${ST}
L  = ${L}
O  = ${O}
OU = ${OU}
CN = ${COMMON_NAME}

[v3_req]
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
EOF

# Add DNS entries
count=1
for name in $SAN_DNS; do
    echo "DNS.$count = $name" >> "${CONFIG_FILE}"
    ((count++))
done

# Add IP entries
count=1
for ip in $SAN_IP; do
    echo "IP.$count = $ip" >> "${CONFIG_FILE}"
    ((count++))
done

echo "--- Generating Private Key and CSR for ${COMMON_NAME} with SANs ---"

openssl req -new -nodes -newkey rsa:${KEY_SIZE} -keyout "${KEY_FILE}" -out "${CSR_FILE}" -config "${CONFIG_FILE}"

echo "--- Process Complete ---"
echo "Private Key saved to: ${KEY_FILE}"
echo "CSR saved to: ${CSR_FILE}"
echo "Config file saved to: ${CONFIG_FILE}"

echo ""
echo "--- Verifying CSR details and SAN attributes ---"
openssl req -text -noout -verify -in "${CSR_FILE}"
