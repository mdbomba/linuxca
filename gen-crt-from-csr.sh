#!/bin/bash
# filename - gen-crt-from-csr.sh
# version - 20250721-02
# description - Signs a server certificate from an existing CSR file with SAN support
# restrictions - Must be run as root to access CA keys in /root/myCA
# usage - sudo bash gen-crt-from-csr.sh [csr_file]

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

save_vars

# CA SPECIFIC PARAMETERS
dir="$CA_DIR"
CA_KEY="$dir/intermediateCA/private/intermediate.key.pem"
CA_CHAIN="$dir/intermediateCA/certs/intermediate.chain.pem"
CA_CRT="$dir/intermediateCA/certs/intermediate.cert.pem"
VALIDITY_DAYS=365

# Verify CA files exist
for f in "$CA_KEY" "$CA_CHAIN" "$CA_CRT"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: CA file not found: $f"
        echo "Have you run build-ca.sh first?"
        exit 1
    fi
done

echo "CA PARAMETERS SET"

# REQUEST Certificate Signing Request file
SERVER_CSR="${1:-}"
while [ ! -f "${SERVER_CSR}" ]; do
    read -p "Enter name of csr file : " SERVER_CSR
done

echo "CSR FILE IS $SERVER_CSR"

# EXTRACT BASE FILENAME
BASE=$(basename "$SERVER_CSR" .csr)

echo "BASE NAME = $BASE"

# CREATE FILE NAMES FOR WORKING FILES
SERVER_CRT="$BASE.crt"
SERVER_CFG="$BASE.cfg"
SERVER_CHAIN="$BASE.chain"

# Copy CA Chain to Server Chain
cp "$CA_CHAIN" "$SERVER_CHAIN"

# Extract common name (CN) from csr file
CN=$(openssl req -in "${SERVER_CSR}" -noout -subject | sed -n 's/.*CN = \([^,/]*\).*/\1/p')
echo "Common Name: $CN"

# EXTRACT SAN DATA FROM THE CSR FILE
echo "--- Extracting SAN data from CSR file... ---"
SAN_ENTRIES=$(openssl req -in "${SERVER_CSR}" -text -noout | grep 'X509v3 Subject Alternative Name:' -A 1 | tail -n 1 | sed 's/^[[:space:]]*//' | sed 's/IP Address:/IP:/g')

# CHECK if CSR file includes SAN attributes (terminate if none)
if [ -z "${SAN_ENTRIES}" ]; then
    echo "CSR request does not include SAN attributes. Terminating Script"
    exit 1
fi

echo "CSR FILE = $SERVER_CSR"
echo "CFG FILE = $SERVER_CFG"
echo "CHAIN FILE = $SERVER_CHAIN"
echo "CN = $CN"
echo "SAN ENTRIES = $SAN_ENTRIES"

# CREATE CONFIG FILE FOR SERVICING CSR
cat <<EOF > "${SERVER_CFG}"
[v3_req]
authorityKeyIdentifier = keyid,issuer
basicConstraints       = CA:FALSE
keyUsage               = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage       = serverAuth
subjectAltName         = ${SAN_ENTRIES}
EOF

echo ""
echo "CONFIG FILE TO BE USED FOR CERTIFICATE CREATION IS LISTED BELOW"
echo ""
cat "${SERVER_CFG}"
echo ""

# GENERATE AND VERIFY SERVER SAN CERTIFICATE
echo "--- Generating Server Certificate ---"
openssl x509 -req -days ${VALIDITY_DAYS} \
    -in "${SERVER_CSR}" \
    -CA "${CA_CRT}" \
    -CAkey "${CA_KEY}" \
    -CAcreateserial \
    -out "${SERVER_CRT}" \
    -extensions v3_req \
    -extfile "${SERVER_CFG}"

echo ""
echo "Verifying certificate against chain..."
openssl verify -CAfile "${SERVER_CHAIN}" "${SERVER_CRT}"

echo ""
echo "Output certificate - check to ensure SAN entries are correct"
echo ""
openssl x509 -in "${SERVER_CRT}" -text -noout
echo ""
echo "Files associated with this request:"
ls -la ${BASE}*
