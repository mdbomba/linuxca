#!/bin/bash
# filename - gen-crt-from-csr.sh
# version - 20261006-01
# description - Signs an existing server CSR and preserves its subject alternative names.
# run as - Regular user; sudo is requested only to read the CA private key.

set -euo pipefail

OUTPUT_DIR="$HOME/certs"
mkdir -p "$OUTPUT_DIR"

RCA_CERT="/opt/myCA/public/rca.crt"
ICA_CERT="/opt/myCA/public/ica.crt"
CHAIN_CERT="/opt/myCA/public/chain.crt"
ICA_KEY="/root/myCA/intermediateCA/private/intermediate.key.pem"
VALIDITY_DAYS=365

prompt_var() {
    local var_name="$1"
    local prompt_msg="$2"
    local current_val="${!var_name:-}"

    if [[ -z "$current_val" ]]; then
        read -r -p "$prompt_msg" "$var_name"
    fi
}

require_file() {
    if sudo test ! -r "$1"; then
        echo "TERMINAL ERROR: Required file not found: $1" >&2
        exit 1
    fi
}

if ! command -v openssl > /dev/null; then
    sudo apt install -y openssl
fi

if ! command -v zip > /dev/null; then
    sudo apt install -y zip
fi

prompt_var password "Enter password for PFX and ZIP archive [password]: "
password="${password:-password}"

CSR="${1:-}"
prompt_var CSR 'Enter CSR file path: '
if [[ ! -f "$CSR" ]]; then
    echo "TERMINAL ERROR: Required file not found: $CSR" >&2
    exit 1
fi

fname="$(basename "$CSR" .csr)"
prompt_var Name "Enter certificate file name prefix [$fname]: "
Name="${Name:-$fname}"


CRT="${OUTPUT_DIR}/${Name}.crt"
CNF="${OUTPUT_DIR}/${Name}.cfg"
ZIP="${OUTPUT_DIR}/${Name}.zip"

CHAIN="${OUTPUT_DIR}/ca_chain.crt"
ICA="${OUTPUT_DIR}/ca_ica.crt"
RCA="${OUTPUT_DIR}/ca_rca.crt"

OUTPUTS=("$CRT" "$CNF" "$ZIP")

for output in "${OUTPUTS[@]}"; do
    if [[ -e "$output" ]]; then
        read -r -p "Certificates already exist: ${output}. Replace it? [y/N]: " replace_output
        if [[ "$replace_output" =~ ^[Yy]$ ]]; then
            rm -f "$output"
        else
            printf "Retaining existing output: %s\n" "$output"
            exit 0
        fi
    fi
done

require_file "$RCA_CERT"
require_file "$ICA_CERT"
require_file "$CHAIN_CERT"
require_file "$ICA_KEY"
require_file "$CSR"

CN="$(openssl req -in "$CSR" -noout -subject | sed -n 's/.*CN[[:space:]]*=[[:space:]]*\([^,/]*\).*/\1/p')"
SAN_ENTRIES="$(openssl req -in "$CSR" -text -noout | sed -n '/X509v3 Subject Alternative Name:/ {n; s/^[[:space:]]*//; s/IP Address:/IP:/g; p;}')"

if [[ -z "$CN" ]]; then
    printf "ERROR: CSR does not contain a Common Name.\n" >&2
    exit 1
fi
if [[ -z "$SAN_ENTRIES" ]]; then
    printf "ERROR: CSR does not contain subject alternative names.\n" >&2
    exit 1
fi

install -m 0644 "$CHAIN_CERT" "$CHAIN"
install -m 0644 "$ICA_CERT" "$ICA"
install -m 0644 "$RCA_CERT" "$RCA"


cat > "$CNF" <<EOF
[v3_req]
authorityKeyIdentifier = keyid,issuer
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = ${SAN_ENTRIES}
EOF

sudo openssl x509 -req -days "$VALIDITY_DAYS" -in "$CSR" \
    -CA "$ICA_CERT" -CAkey "$ICA_KEY" -CAcreateserial -out "$CRT" \
    -extensions v3_req -extfile "$CNF"

sudo chown "$(id -un):$(id -gn)" "$CRT"
chmod 644 "$CRT" "$CNF" "$CHAIN"

openssl verify -purpose sslserver -CAfile "$CHAIN" "$CRT"

zip -j -P "$password" "$ZIP" "$CRT" "$CHAIN" "$ICA" "$RCA"

printf "Created certificate material in %s:\n" "$OUTPUT_DIR"
printf "  CSR: %s\n  Subject: %s\n  Certificate: %s\n  Chain: %s\n  Config: %s\n" \
    "$CSR" "$CN" "$CRT" "$CHAIN" "$CNF"
