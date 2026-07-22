#!/bin/bash
# filename - gen-crt-and-key.sh
# version - 20250721-02
# description - Generates a server private key, CSR, signed TLS certificate, and PFX file
# restrictions - Must be run as root to access CA keys
# usage - sudo bash gen-crt-and-key.sh

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root."
    exit 1
fi

export TERM=linux
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Ensure zip is installed
if ! command -v zip &> /dev/null; then
    echo "zip command not found. Installing..."
    apt-get update -qq && apt-get install -y -qq zip
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
prompt_var Name "Enter file name prefix (e.g. chef360): "
prompt_var CN "Enter Common Name / FQDN (e.g. chef360.demo.lab): "
prompt_var CN2 "Enter short hostname (e.g. chef360): "
prompt_var IP1 "Enter primary IP address: "

# Optional
if [ -z "$IP2" ]; then
    read -p "Enter secondary IP address (or press enter to skip): " IP2
fi
if [ -z "$password" ]; then
    read -p "Enter password for PFX and ZIP archive [password]: " password
    password="${password:-password}"
fi

save_vars

# Debug mode
debug="${debug:-no}"

######################################################################################
dir="$CA_DIR"
pwd=$(pwd)
ica_cert="$dir/intermediateCA/certs/intermediate.cert.pem"
ica_chain="$dir/intermediateCA/certs/intermediate.chain.pem"
ica_key="$dir/intermediateCA/private/intermediate.key.pem"
rca_cert="$dir/rootCA/certs/ca.cert.pem"
csr="${pwd}/${Name}.csr"
cnf="${pwd}/${Name}.cnf"
key="${pwd}/${Name}.key"
crt="${pwd}/${Name}.crt"
chain="${pwd}/${Name}_ica.chain"
ica="${pwd}/${Name}_ica.crt"
rca="${pwd}/${Name}_rca.crt"
archive="${pwd}/${Name}_certs.zip"
pfx_file="${pwd}/${Name}.pfx"
[[ -n "$password" ]] && PASS_ARG="-passout pass:$password"
[[ -z "$password" ]] && PASS_ARG=""
[[ -n "$password" ]] && PASS_ARG2="-jP ${password}"
[[ -z "$password" ]] && PASS_ARG2="-j"
######################################################################################

# Verify CA files exist
for f in "$ica_cert" "$ica_chain" "$ica_key" "$rca_cert"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: CA file not found: $f"
        echo "Have you run build-ca.sh first?"
        exit 1
    fi
done

######################################################################################
#                     COPY CA CERT AND CHAIN FILES                                   #
######################################################################################
cp "$ica_chain" "${chain}"
cp "$ica_cert" "${ica}"
cp "$rca_cert" "${rca}"

######################################################################################
#        CONSTRUCT OPENSSL CONFIG FILE FOR SAN CERTS                                 #
######################################################################################
SAN_LIST=()
[[ -n "$CN" ]]  && SAN_LIST+=("DNS:${CN}")
[[ -n "$CN2" ]] && SAN_LIST+=("DNS:${CN2}")
[[ -n "$IP1" ]] && SAN_LIST+=("IP:${IP1}")
[[ -n "$IP2" ]] && SAN_LIST+=("IP:${IP2}")
SAN_VALUE=$(IFS=,; echo "${SAN_LIST[*]}")

cat << EOF > "$cnf"
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
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = $SAN_VALUE
EOF

######################################################################################
#                           DEBUG SECTION                                             #
######################################################################################
if [ "$debug" = "yes" ]; then
  echo ""
  echo " --- CONFIGURATION VARIABLES --- "
  echo "C=$C  O=$O  OU=$OU  CN=$CN  CN2=$CN2  IP1=$IP1  IP2=$IP2"
  echo "Name=$Name"
  echo "--- CONTENTS OF OPENSSL CONFIG FILE ---"
  cat "$cnf"
  echo ""
  read -p "Press Enter to continue: "
fi

######################################################################################
#                       CREATE SERVER KEY FILE                                        #
######################################################################################
echo ""
echo -e "${GREEN}Creating key file named [ ${YELLOW}${key}${GREEN} ]${NC}"
openssl req -newkey rsa:2048 -nodes -keyout "${key}" -out "${csr}" \
  -subj "/CN=$CN/OU=$OU/O=$O/C=$C" -config "${cnf}" -batch

echo ""
echo -e "${GREEN}Verifying key file named [ ${YELLOW}${key}${GREEN} ]${NC}"
openssl rsa -in "${key}" -check -noout

######################################################################################
#                        CREATE SERVER CRT FILE                                      #
######################################################################################
echo ""
echo -e "${GREEN}Creating crt file named [ ${YELLOW}${crt}${GREEN} ]${NC}"
openssl x509 -req -in "${csr}" -CA "${ica_cert}" -CAkey "${ica_key}" \
  -CAcreateserial -out "${crt}" -days 365 -sha256 \
  -extfile "${cnf}" -extensions v3_req

echo ""
echo -e "${GREEN}Verify certificate file named [ ${YELLOW}${crt}${GREEN} ]${NC}"
openssl verify -CAfile "${chain}" "${crt}"

echo ""
echo -e "${GREEN}Display certificate file named [ ${YELLOW}${crt}${GREEN} ]${NC}"
openssl x509 -in "${crt}" -text -noout

######################################################################################
#                        CREATE SERVER PFX FILE                                      #
######################################################################################
echo ""
echo -e "${GREEN}Creating PFX file: ${YELLOW}${pfx_file}${NC}"
openssl pkcs12 -export -out "$pfx_file" \
  -inkey "${key}" -in "${crt}" -certfile "${chain}" $PASS_ARG

######################################################################################
#            CREATE ARCHIVE PACKAGE FOR ALL GENERATED FILES                           #
######################################################################################
echo ""
echo -e "${GREEN}Creating ZIP archive: ${YELLOW}${archive}${NC}"
zip $PASS_ARG2 "${archive}" "${crt}" "${key}" \
  "${chain}" "${ica}" "${rca}" "${pfx_file}"

######################################################################################
#                    DISPLAY CRITICAL INFORMATION                                     #
######################################################################################
echo ""
echo "#########################################################################"
echo -e "${GREEN}***** CONTENTS OF ARCHIVE FILE [ ${YELLOW}${archive}${NC} ] "
echo ""
zip -sf "$archive"
echo ""
echo "#########################################################################"
echo ""
echo -e "${GREEN}***** DECRYPT PASSWORD FOR PFX AND ARCHIVE FILE IS [ ${YELLOW}${password}${NC} ]"
echo ""
echo "#########################################################################"
echo "###########          LIST OF ALL GENERATED FILES              ###########"
echo ""
ls -la "${pwd}/${Name}"*
echo ""
echo -e "${YELLOW}#########################################################################"
echo -e "###########              END OF SCRIPT                        ###########"
echo -e "#########################################################################${NC}"
