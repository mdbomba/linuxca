#!/bin/bash
#
export TERM=linux
RED='\033[0;31m'
GREEN='\033[0;32m'  # echo -e "${GREEN}ZIP Archive created"
YELLOW='\033[0;33m'
NC='\033[0m'        # No Color (resets back to default)
# 
# Ensure zip is installed 
if ! command -v zip &> /dev/null; then
    echo "zip command not found. Installing..."
    sudo apt update && sudo apt install zip -y
fi
#
######################################################################################
#          START OF PARAMETERS THAT CAN BE EDITED BEFORE RUNNING SCRIPT              #
######################################################################################
debug="no"                  # yes will dump debug data, any other value will not
password="password"         # Used to encrypt zip archive file and pfx certificate file
Name="chef360"              # Root Name used to name all generated files
CN="chef360.demo.lab"       # FQDN for site requesting certificate
CN2="chef360"               # Hostname for site requesting certificate
IP1="10.0.0.50"             # Primary IP address for site requesting certificate
IP2=""                      # Secondary IP address for site requesting certificate
######################################################################################
#           END OF PARAMETERS THAT CAN BE EDITED BEFORE RUNNING SCRIPT               #
######################################################################################
#
######################################################################################
#  START OF PARAMETERS THAT SHOULD NOT BE EDITED UNLESS YOU KNOW WHAT YOU ARE DOING  #
######################################################################################
pwd=$(pwd)
ica_cert="/root/myCA/intermediateCA/certs/intermediate.cert.pem"
ica_chain="/root/myCA/intermediateCA/certs/intermediate.chain.pem"
ica_key="/root/myCA/intermediateCA/private/intermediate.key.pem"
rca_cert="/root/myCA/rootCA/certs/ca.cert.pem"
C="US"
O="lab"
OU="demo"
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
#   END OF PARAMETERS THAT SHOULD NOT BE EDITED UNLESS YOU KNOW WHAT YOU ARE DOING   #
######################################################################################
#
######################################################################################
#                     START COPYING CA CERT AND CHAIN FILES                          #
######################################################################################
sudo cp $ica_chain "${chain}" && sudo chown "$USER:$USER" "${chain}"
sudo cp $ica_cert "${ica}" && sudo chown "$USER:$USER" "${ica}"
sudo cp $rca_cert "${rca}" && sudo chown "$USER:$USER" "${rca}"
######################################################################################
#                      END COPYING CA CERT AND CHAIN FILES                           #
######################################################################################
#
######################################################################################
#        START CONSTRUCTION OF OENSSL CONFIG FILE NEEDED TO ISSUE SAN CERTS          #
######################################################################################
# --- Construct the SAN (Subject Alternative Names) string dynamically ---
SAN_LIST=()
[[ -n "$CN" ]]  && SAN_LIST+=("DNS:${CN}")
[[ -n "$CN2" ]] && SAN_LIST+=("DNS:${CN2}")
[[ -n "$IP1" ]] && SAN_LIST+=("IP:${IP1}")
[[ -n "$IP2" ]] && SAN_LIST+=("IP:${IP2}")
# Join array elements with commas (e.g., "DNS:chef360.demo.lab,IP:10.0.0.50")
SAN_VALUE=$(IFS=,; echo "${SAN_LIST[*]}")
# --- Create the OpenSSL Config File ---
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
#          END CONSTRUCTION OF OENSSL CONFIG FILE NEEDED TO ISSUE SAN CERTS          #
######################################################################################
#
######################################################################################
#                           START OF DEBUG SECTION                                   #
######################################################################################
if [ "$debug" = "yes" ]; then
  echo ""
  echo " --- CONFIGURATION VARIABLES BOTH STATIC AND DYNAMIC --- "
  echo "C= $C"
  echo "O= $O"
  echo "OU= $OU"
  echo "CN = $CN"
  echo "CN2 = $CN2"
  echo "IP1 = $IP1"
  echo "IP2 = $IP2"
  echo "Name= $Name"
  echo "ica_cert= $ica_cert"
  echo "ica_chain= $ica_chain"
  echo "ica_key= $ica_key"
  echo "rca_cert= $rca_cert"
  echo ""
  echo "csr= $csr"
  echo "cnf= $cnf"
  echo "key= $key"
  echo "crt= $crt"
  echo "chain= $chain"
  echo "ica= $ica"
  echo "rca= $rca"
  echo "archive= $archive"
  echo "pfx_file= $pfx_file"
  echo "password= $password"
  echo "--- CONTENTS OF OPENSSL CONFIG FILE ---"
  cat $cnf
  echo " ------------------------------------------------------- "
  echo ""
  echo -n "Press Enter to continue to build certs: "
  read Z
fi
######################################################################################
#                             END OF DEBUG SECTION                                   #
######################################################################################
#
######################################################################################
#                       START CREATION OF SERVER KEY FILE                            #
######################################################################################
# --- Create key file --- 
echo ""
echo -e "${GREEN}Creating key file named [ ${YELLOW}${key}${GREEN} ]${NC}"
openssl req -newkey rsa:2048 -nodes -keyout "${key}" -out "${csr}" \
-subj "/CN=$CN/OU=$OU/O=$O/C=$C" -config "${cnf}" -batch
sleep 2
# --- Verifying key file --- 
echo ""
echo -e "${GREEN}Verifying key file named [ ${YELLOW}${key}${GREEN} ]${NC}"
openssl rsa -in "${key}" -check -noout
sleep 2
######################################################################################
#                         END CREATION OF SERVER KEY FILE                            #
######################################################################################
#
######################################################################################
#                        START CREATION OF SERVER CRT FILE                           #
######################################################################################
# --- Create crt file --- 
echo ""
echo -e "${GREEN}Creating crt file named [ ${YELLOW}${crt}${GREEN} ]${NC}"
sudo openssl x509 -req -in "${csr}" -CA "${ica_cert}" -CAkey "${ica_key}" \
-CAcreateserial -out "${crt}" -days 365 -sha256 \
-extfile "${cnf}" -extensions v3_req > /dev/null
sleep 2
sudo chown $USER:$USER "$crt"
# --- Verifying crt file ---
echo ""
echo -e "${GREEN}Verify certificate file named [ ${YELLOW}${crt}${GREEN} ]${NC}"
openssl verify -CAfile "${chain}" "${crt}"
sleep 2
# --- Displaying crt file ---
echo ""
echo -e "${GREEN}Display certificate file named [ ${YELLOW}${crt}${GREEN} ]${NC}"
sudo openssl x509 -in "${crt}" -text -noout
sleep 2
######################################################################################
#                         END CREATION OF SERVER CRT FILE                            #
######################################################################################
#
######################################################################################
#                        START CREATION OF SERVER PFX FILE                           #
######################################################################################
echo ""
echo -e "${GREEN}Creating PFX file: ${YELLOW}${pfx_file}${NC}"
openssl pkcs12 -export -out "$pfx_file" \
-inkey "${key}" -in "${crt}" -certfile "${chain}" $PASS_ARG
######################################################################################
#                         END CREATION OF SERVER KEY FILE                            #
######################################################################################
#
######################################################################################
#            START CREATION OF ARCHIVE PACKAGE FOR ALL GENERATED FILES               #
######################################################################################
echo ""
echo -e "${GREEN}Creating ZIP archive: $YELLOW}${archive}${NC}"
sudo zip $PASS_ARG2 "${archive}" "${crt}" "${key}" \
"${chain}" "${ica}" "${rca}" "${pfx_file}"
sudo chown "$USER:$USER" "${archive}"
######################################################################################
#              END CREATION OF ARCHIVE PACKAGE FOR ALL GENERATED FILES               #
######################################################################################
#
######################################################################################
#                    START DISPLAY OF CRITICAL INFORMATION                           #
######################################################################################
echo ""
echo "#########################################################################"
echo -e "${GREEN}***** CONTENTS OF ARCHIVE FILE [ ${YELLOW}${archive}${NC} ] "
echo ""
zip -sf "$archive"
echo ""
echo "#########################################################################"
echo ""
echo "#########################################################################"
echo -e "${GREEN}***** DECRYPT PASSWORD FOR PFX AND ARCHIVE FILE IS [ ${YELLOW}${password}${NC} ]   ****** "
echo "#########################################################################"
echo ""
echo "#########################################################################"
echo "###########          LIST OF ALL GENERATED FILES              ###########"
echo ""
ls -la "${pwd}/${Name}"*
echo ""
echo "#########################################################################"
echo ""
echo -e "${YELLOW}#########################################################################"
echo -e "${YELLOW}###########              END OF SCRIPT                        ###########"
echo -e "${YELLOW}#########################################################################"



