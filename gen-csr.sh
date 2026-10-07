#!/bin/bash
# filename - gen-csr.sh
# version - 20261006-01
# description - Generates a private key and CSR with SAN support.
# run as - Regular user; this workflow does not require CA access.

set -euo pipefail

OUTPUT_DIR="$HOME/certs"
mkdir -p "$OUTPUT_DIR"

prompt_var() {
    local var_name="$1"
    local prompt_msg="$2"
    local current_val="${!var_name:-}"

    if [[ -z "$current_val" ]]; then
        read -r -p "$prompt_msg" "$var_name"
    fi
}

if ! command -v openssl > /dev/null; then
    sudo apt install -y openssl
fi

prompt_var C 'Enter 2 letter Country Code [US]: '
C="${C:-US}"
prompt_var ST 'Enter State or Province [AZ]: '
ST="${ST:-AZ}"
prompt_var L 'Enter Locality Name [Cochise]: '
L="${L:-Cochise}"
prompt_var O 'Enter Organization Name [lab]: '
O="${O:-lab}"
prompt_var OU 'Enter Organizational Unit Name [demo]: '
OU="${OU:-demo}"
prompt_var CN2 'Enter short hostname [server]: '
CN2="${CN2:-server}"
prompt_var CN "Enter host FQDN [$CN2.$OU.$O]: "
CN="${CN:-$CN2.$OU.$O}"
prompt_var Name "Enter certificate file name prefix [$CN2]: "
Name="${Name:-$CN2}"
IP1=""
while [[ ! "$IP1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; do
    read -r -p "Enter primary IPv4 address: " IP1
done
prompt_var IP2 "Enter secondary IP address (press Enter for none): "

KEY="${OUTPUT_DIR}/${Name}.key"
CSR="${OUTPUT_DIR}/${Name}.csr"
CNF="${OUTPUT_DIR}/${Name}.cnf"
OUTPUTS=("$KEY" "$CSR" "$CNF")

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

SAN_LIST=("DNS:${CN}" "DNS:${CN2}" "IP:${IP1}")
[[ -z "${IP2:-}" ]] || SAN_LIST+=("IP:${IP2}")
SAN_VALUE="$(IFS=,; printf "%s" "${SAN_LIST[*]}")"

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

chmod 600 "$KEY"
chmod 644 "$CSR" "$CNF"

printf 'Created CSR material in %s:\n' "$OUTPUT_DIR"
printf '  %s\n' "${OUTPUTS[@]}"
openssl req -text -noout -verify -in "$CSR"
