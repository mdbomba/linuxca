#!/bin/bash
# filename - gen-crt-and-key.sh
# version - 20260919-01
# description - Generates a server private key, CSR, signed TLS certificate, and PFX file.
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

if ! command -v zip > /dev/null; then
    sudo apt install -y zip
fi

OUTPUT_DIR="$(pwd -P)"
RCA_CERT="/opt/myCA/public/rca.crt"
ICA_CERT="/opt/myCA/public/ica.crt"
ICA_CA_CERT="/root/myCA/intermediateCA/certs/intermediate.cert.pem"
ICA_KEY="/root/myCA/intermediateCA/private/intermediate.key.pem"

prompt_var password 'Enter password for PFX and ZIP archive [password]: '
password="${password:-password}"
prompt_var C 'Enter 2 letter Country Code [US]: '
C="${C:-US}"
prompt_var ST 'Enter State or Province [AZ]: '
ST="${ST:-AZ}"
prompt_var L 'Enter Locality Name [Cochise]: '
L="${L:-Cochise}"
prompt_var O 'Enter Organization Name [DemoLab]: '
O="${O:-DemoLab}"
prompt_var OU 'Enter Organizational Unit Name [Engineering]: '
OU="${OU:-Engineering}"
prompt_var Name 'Enter certificate file name prefix [chef360]: '
Name="${Name:-chef360}"
prompt_var CN 'Enter Common Name / FQDN [chef360.demo.lab]: '
CN="${CN:-chef360.demo.lab}"
prompt_var CN2 "Enter short hostname [${Name}]: "
CN2="${CN2:-$Name}"
while [[ ! "$IP1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; do
    read -r -p 'Enter primary IPv4 address: ' IP1
done
prompt_var IP2 'Enter secondary IP address (press Enter for none): '

CSR="${OUTPUT_DIR}/${Name}.csr"
CNF="${OUTPUT_DIR}/${Name}.cnf"
KEY="${OUTPUT_DIR}/${Name}.key"
CRT="${OUTPUT_DIR}/${Name}.crt"
CHAIN="${OUTPUT_DIR}/${Name}_chain.crt"
ICA="${OUTPUT_DIR}/${Name}_ica.crt"
RCA="${OUTPUT_DIR}/${Name}_rca.crt"
ARCHIVE="${OUTPUT_DIR}/${Name}_certs.zip"
PFX_FILE="${OUTPUT_DIR}/${Name}.pfx"
OUTPUTS=("$CSR" "$CNF" "$KEY" "$CRT" "$CHAIN" "$ICA" "$RCA" "$ARCHIVE" "$PFX_FILE")

for output in "${OUTPUTS[@]}"; do
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

SAN_LIST=("DNS:${CN}" "DNS:${CN2}" "IP:${IP1}")
[[ -z "${IP2:-}" ]] || SAN_LIST+=("IP:${IP2}")
SAN_VALUE="$(IFS=,; printf '%s' "${SAN_LIST[*]}")"

install -m 0644 "$ICA_CERT" "$ICA"
install -m 0644 "$RCA_CERT" "$RCA"
cat "$ICA_CERT" "$RCA_CERT" > "$CHAIN"

cat > "$CNF" <<EOF
[req]
default_bits       = 2048
distinguished_name = req_distinguished_name
req_extensions     = v3_req
prompt             = no

[req_distinguished_name]
C  = $C
O  = $O
OU = $OU
CN = $CN

[v3_req]
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = $SAN_VALUE
EOF

openssl req -newkey rsa:2048 -nodes -keyout "$KEY" -out "$CSR" \
    -subj "/CN=$CN/OU=$OU/O=$O/C=$C" -config "$CNF" -batch
openssl rsa -in "$KEY" -check -noout

sudo openssl x509 -req -in "$CSR" -CA "$ICA_CA_CERT" -CAkey "$ICA_KEY" \
    -CAcreateserial -out "$CRT" -days 365 -sha256 \
    -extfile "$CNF" -extensions v3_req
sudo chown "$(id -un):$(id -gn)" "$CRT"

openssl verify -purpose sslserver -CAfile "$CHAIN" "$CRT"
openssl pkcs12 -export -out "$PFX_FILE" -inkey "$KEY" -in "$CRT" \
    -certfile "$CHAIN" -passout "pass:${password}"
zip -j -P "$password" "$ARCHIVE" "$CRT" "$KEY" "$CHAIN" "$ICA" "$RCA" "$PFX_FILE"

chmod 600 "$KEY" "$PFX_FILE" "$ARCHIVE"
chmod 644 "$CSR" "$CNF" "$CRT" "$CHAIN" "$ICA" "$RCA"

printf 'Created certificate material in %s:\n' "$OUTPUT_DIR"
printf '  %s\n' "${OUTPUTS[@]}"
