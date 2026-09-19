#!/bin/bash
# filename - gen-crt-from-csr.sh
# version - 20260919-01
# description - Signs an existing server CSR and preserves its subject alternative names.
# run as - Regular user; sudo is requested only to read the CA private key.

set -euo pipefail

prompt_var() {
    local var_name="$1"
    local prompt_msg="$2"
    local current_val="${!var_name:-}"

    if [[ -z "$current_val" ]]; then
        read -r -p "$prompt_msg" "$var_name"
    fi
}

require_file() {
    if [[ ! -f "$1" ]]; then
        printf 'ERROR: Required file not found: %s\n' "$1" >&2
        exit 1
    fi
}

if ! command -v openssl > /dev/null; then
    sudo apt install -y openssl
fi

OUTPUT_DIR="$(pwd -P)"
RCA_CERT="/opt/myCA/public/rca.crt"
ICA_CERT="/opt/myCA/public/ica.crt"
ICA_CA_CERT="/root/myCA/intermediateCA/certs/intermediate.cert.pem"
ICA_KEY="/root/myCA/intermediateCA/private/intermediate.key.pem"
VALIDITY_DAYS=365

SERVER_CSR="${1:-}"
prompt_var SERVER_CSR 'Enter CSR file path: '
require_file "$SERVER_CSR"

BASE_NAME="$(basename "$SERVER_CSR" .csr)"
SERVER_CRT="${OUTPUT_DIR}/${BASE_NAME}.crt"
SERVER_CFG="${OUTPUT_DIR}/${BASE_NAME}.cfg"
SERVER_CHAIN="${OUTPUT_DIR}/${BASE_NAME}_chain.crt"

for output in "$SERVER_CRT" "$SERVER_CFG" "$SERVER_CHAIN"; do
    if [[ -e "$output" ]]; then
        read -r -p "Output already exists: ${output}. Replace it? [y/N]: " replace_output
        if [[ "$replace_output" =~ ^[Yy]$ ]]; then
            rm -f "$output"
        else
            printf 'Retaining existing output: %s\n' "$output"
            exit 0
        fi
    fi
done

require_file "$RCA_CERT"
require_file "$ICA_CERT"
if ! sudo test -r "$ICA_KEY"; then
    printf 'ERROR: Cannot read intermediate CA key: %s\n' "$ICA_KEY" >&2
    exit 1
fi

CN="$(openssl req -in "$SERVER_CSR" -noout -subject | sed -n 's/.*CN[[:space:]]*=[[:space:]]*\([^,/]*\).*/\1/p')"
SAN_ENTRIES="$(openssl req -in "$SERVER_CSR" -text -noout | sed -n '/X509v3 Subject Alternative Name:/ {n; s/^[[:space:]]*//; s/IP Address:/IP:/g; p;}')"

if [[ -z "$CN" ]]; then
    printf 'ERROR: CSR does not contain a Common Name.\n' >&2
    exit 1
fi
if [[ -z "$SAN_ENTRIES" ]]; then
    printf 'ERROR: CSR does not contain subject alternative names.\n' >&2
    exit 1
fi

cat "$ICA_CERT" "$RCA_CERT" > "$SERVER_CHAIN"

cat > "$SERVER_CFG" <<EOF
[v3_req]
authorityKeyIdentifier = keyid,issuer
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = ${SAN_ENTRIES}
EOF

sudo openssl x509 -req -days "$VALIDITY_DAYS" -in "$SERVER_CSR" \
    -CA "$ICA_CA_CERT" -CAkey "$ICA_KEY" -CAcreateserial -out "$SERVER_CRT" \
    -extensions v3_req -extfile "$SERVER_CFG"
sudo chown "$(id -un):$(id -gn)" "$SERVER_CRT"
chmod 644 "$SERVER_CRT" "$SERVER_CFG" "$SERVER_CHAIN"

openssl verify -purpose sslserver -CAfile "$SERVER_CHAIN" "$SERVER_CRT"
printf 'Created certificate material in %s:\n' "$OUTPUT_DIR"
printf '  CSR: %s\n  Subject: %s\n  Certificate: %s\n  Chain: %s\n  Config: %s\n' \
    "$SERVER_CSR" "$CN" "$SERVER_CRT" "$SERVER_CHAIN" "$SERVER_CFG"
