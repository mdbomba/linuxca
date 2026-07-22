#!/bin/bash
# filename - build-ca.sh
# version - 20250721-02
# description - Script to create a linux Root and Intermediate certificate authority
# restrictions - Script must be run as root
# CA hierarchy is created in the location specified by CA_DIR in ca-vars.conf

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
    echo "Variables saved to $VARS_FILE"
}

load_vars

prompt_var CA_DIR "Enter CA directory path [/root/myCA]: "
CA_DIR="${CA_DIR:-/root/myCA}"
prompt_var C "Enter Country Name (2 letter code): "
prompt_var ST "Enter State or Province Name: "
prompt_var L "Enter Locality Name: "
prompt_var O "Enter Organization Name: "
prompt_var OU "Enter Organizational Unit Name: "

save_vars

dir="$CA_DIR"

# Ensure tree is installed
apt install -y -qq tree

# CREATE DIRECTORY AND DEFAULT FILE STRUCTURES
mkdir -p  $dir/rootCA/{certs,crl,newcerts,private,csr}
mkdir -p  $dir/intermediateCA/{certs,crl,newcerts,private,csr}
echo 1000 > $dir/rootCA/serial
echo 1000 > $dir/intermediateCA/serial
echo 0100 > $dir/rootCA/crlnumber 
echo 0100 > $dir/intermediateCA/crlnumber
touch     $dir/rootCA/index.txt
touch     $dir/intermediateCA/index.txt

echo ""
echo "Directory structure for CA created. See below"
tree $dir
echo ""

read -p "If directory structure is correct, press enter, else press CTRL-C and fix script. : " 

# CREATE CONFIG FILE FOR ROOT CERTIFICATE
ROOTCNF="$dir/openssl_root.cnf"

cat <<EOF > "$ROOTCNF"
[ ca ]
default_ca              = CA_default

[ CA_default ]
dir                     = $dir/rootCA
certs                   = $dir/rootCA/certs
crl_dir                 = $dir/rootCA/crl
new_certs_dir           = $dir/rootCA/newcerts
database                = $dir/rootCA/index.txt
serial                  = $dir/rootCA/serial
RANDFILE                = $dir/rootCA/private/.rand
private_key             = $dir/rootCA/private/ca.key.pem
certificate             = $dir/rootCA/certs/ca.cert.pem
crl                     = $dir/rootCA/crl/ca.crl.pem
crlnumber               = $dir/rootCA/crlnumber
crl_extensions          = crl_ext
default_crl_days        = 30
default_md              = sha256
preserve                = no
email_in_dn             = no
name_opt                = ca_default
cert_opt                = ca_default
policy                  = policy_strict
unique_subject          = no

[ policy_strict ]
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits            = 4096
distinguished_name      = req_distinguished_name
string_mask             = utf8only
default_md              = sha256
prompt                  = no

[ req_distinguished_name ]
countryName             = Country Name (2 letter code)
stateOrProvinceName     = State or Province Name (full name)
localityName            = Locality Name (city)
0.organizationName      = Organization Name (company)
organizationalUnitName  = Organizational Unit Name (section)
commonName              = Common Name (your domain)
emailAddress            = Email Address

[ v3_ca ]
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always,issuer
basicConstraints        = critical, CA:true
keyUsage                = critical, keyCertSign, cRLSign

[ crl_ext ]
authorityKeyIdentifier  = keyid:always,issuer

[ v3_intermediate_ca ]
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always,issuer
basicConstraints        = critical, CA:true, pathlen:0
keyUsage                = critical, digitalSignature, cRLSign, keyCertSign
EOF

echo ""
echo "Config file for root certificate created. See below"
echo ""
cat $ROOTCNF
echo ""
read -p "If configuration file is correct press ENTER, else press CTRL-C and fix script : "

# ROOT CA KEY AND CERTIFICATE GENERATION
echo ""
echo "GENERATING ROOT CA PRIVATE KEY"
openssl genrsa -out "$dir/rootCA/private/ca.key.pem" 4096
chmod 400 "$dir/rootCA/private/ca.key.pem"
echo ""
echo "Root CA private key created."
echo ""
echo "SHOW CONTENTS OF PRIVATE KEY"
openssl rsa -noout -text -in "$dir/rootCA/private/ca.key.pem"
echo ""
read -p "If private key appears to be correct press enter, else press CTRL-C and fix script. : "
echo ""

echo "GENERATING ROOT CA PUBLIC CERTIFICATE"
openssl req -config "$ROOTCNF" -key "$dir/rootCA/private/ca.key.pem" -new -x509 -days 7300 -sha256 -extensions v3_ca -out "$dir/rootCA/certs/ca.cert.pem" -subj "/C=$C/ST=$ST/L=$L/O=$O/OU=$OU/CN=Root CA"
chmod 444 "$dir/rootCA/certs/ca.cert.pem"
echo ""
echo "SHOW CONTENT OF ROOT PUBLIC CERTIFICATE"
echo ""
openssl x509 -noout -text -in "$dir/rootCA/certs/ca.cert.pem"
echo ""
read -p "If root CA public certificate appears to be correct press enter, else press CTRL-C and fix script. : "
echo ""

# INTERMEDIATE CA KEY AND CERTIFICATE GENERATION
INTERCNF="$dir/openssl_intermediate.cnf"

cat <<EOF > $INTERCNF
[ ca ]
default_ca              = CA_default

[ CA_default ]
dir                     = $dir/intermediateCA
certs                   = $dir/intermediateCA/certs
crl_dir                 = $dir/intermediateCA/crl
new_certs_dir           = $dir/intermediateCA/newcerts
database                = $dir/intermediateCA/index.txt
serial                  = $dir/intermediateCA/serial
RANDFILE                = $dir/intermediateCA/private/.rand
private_key             = $dir/intermediateCA/private/intermediate.key.pem
certificate             = $dir/intermediateCA/certs/intermediate.cert.pem
crl                     = $dir/intermediateCA/crl/intermediate.crl.pem
crlnumber               = $dir/intermediateCA/crlnumber
crl_extensions          = crl_ext
default_crl_days        = 30
default_md              = sha256
preserve                = no
email_in_dn             = no
name_opt                = ca_default
cert_opt                = ca_default
policy                  = policy_loose

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits            = 4096
distinguished_name      = req_distinguished_name
string_mask             = utf8only
default_md              = sha256
x509_extensions         = v3_intermediate_ca

[ req_distinguished_name ]
countryName             = Country Name (2 letter code)
stateOrProvinceName     = State or Province Name
localityName            = Locality Name
0.organizationName      = Organization Name
organizationalUnitName  = Organizational Unit Name
commonName              = Common Name
emailAddress            = Email Address

[ v3_intermediate_ca ]
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always,issuer
basicConstraints        = critical, CA:true, pathlen:0
keyUsage                = critical, digitalSignature, cRLSign, keyCertSign

[ crl_ext ]
authorityKeyIdentifier  = keyid:always

[ server_cert ]
basicConstraints        = CA:FALSE
nsCertType              = server
keyUsage                = critical, digitalSignature, keyEncipherment
extendedKeyUsage        = serverAuth
authorityKeyIdentifier  = keyid,issuer
subjectKeyIdentifier    = hash
EOF

echo ""
echo "Config file for intermediate certificate created. See below"
echo ""
cat $INTERCNF
echo ""
read -p "If configuration file is correct press ENTER, else press CTRL-C and fix script : "

echo "GENERATING INTERMEDIATE CA PRIVATE KEY"
openssl genrsa -out "$dir/intermediateCA/private/intermediate.key.pem" 4096
chmod 400 "$dir/intermediateCA/private/intermediate.key.pem"
echo ""
echo "Intermediate CA private key created."
echo ""
echo "SHOW CONTENTS OF PRIVATE KEY"
openssl rsa -noout -text -in "$dir/intermediateCA/private/intermediate.key.pem"
echo ""
read -p "If private key appears to be correct press enter, else press CTRL-C and fix script. : "
echo ""

echo "GENERATING CSR TO REQUEST INTERMEDIATE CA PUBLIC CERTIFICATE"
openssl req -config "$INTERCNF" -key "$dir/intermediateCA/private/intermediate.key.pem" -new -sha256 -out "$dir/intermediateCA/csr/intermediate.csr.pem" -subj "/C=$C/ST=$ST/L=$L/O=$O/OU=$OU/CN=Intermediate CA"

echo ""
echo "Certificate Signing Request for Intermediate CA certificate generated, see below"
echo ""
cat "$dir/intermediateCA/csr/intermediate.csr.pem"
echo ""
read -p "If CSR appears to be correct press enter, else press CTRL-C and fix script. : "
echo ""

echo "REQUESTING INTERMEDIATE CA PUBLIC CERTIFICATE USING CSR FILE"
openssl ca -config "$ROOTCNF" -extensions v3_intermediate_ca -days 3650 -notext -md sha256 -in "$dir/intermediateCA/csr/intermediate.csr.pem" -out "$dir/intermediateCA/certs/intermediate.cert.pem"
chmod 444 "$dir/intermediateCA/certs/intermediate.cert.pem"
echo ""
cat "$dir/intermediateCA/certs/intermediate.cert.pem"
echo ""
read -p "If cert appears to be correct press enter, else press CTRL-C and fix script. : "
echo ""

echo "VERIFYING CERTIFICATE FILE IS NOW LOCATED IN THE CA INDEX FILE"
echo ""
cat "$dir/rootCA/index.txt"
echo ""
read -p "If index data appears to be correct press enter, else press CTRL-C and fix script. : "
echo ""

echo "SHOWING CONTENT OF INTERMEDIATE CA PUBLIC CERTIFICATE"
openssl x509 -noout -text -in "$dir/intermediateCA/certs/intermediate.cert.pem"
echo ""
read -p "If cert contents appear to be correct press enter, else press CTRL-C and fix script. : "
echo ""

echo "VERIFYING INTERMEDIATE CERTIFICATE"
openssl verify -CAfile "$dir/rootCA/certs/ca.cert.pem" "$dir/intermediateCA/certs/intermediate.cert.pem"
echo ""
read -p "If cert verification appears to be correct press enter, else press CTRL-C and fix script. : "
echo ""

# CREATE TRUST CHAIN CERTIFICATE
echo "CREATING TRUST CHAIN FILE"
cat "$dir/intermediateCA/certs/intermediate.cert.pem" "$dir/rootCA/certs/ca.cert.pem" > "$dir/intermediateCA/certs/intermediate.chain.pem"
echo ""
echo "Trust chain file contents displayed below"
echo ""
cat "$dir/intermediateCA/certs/intermediate.chain.pem"
echo ""
read -p "If cert chain appears to be correct press enter, else press CTRL-C and fix script. : "
echo ""

echo "VERIFYING CERTIFICATE CHAIN FILE"
openssl verify -CAfile "$dir/intermediateCA/certs/intermediate.chain.pem" "$dir/intermediateCA/certs/intermediate.cert.pem"

# COPY CONVENIENCE FILES TO /root
cp "$dir/intermediateCA/certs/intermediate.cert.pem" /root/ica.crt
cp "$dir/intermediateCA/certs/intermediate.chain.pem" /root/ica.chain
cp "$dir/intermediateCA/private/intermediate.key.pem" /root/ica.key

echo ""
echo "CA build complete. Convenience copies placed in /root/:"
echo "  /root/ica.crt   - Intermediate CA certificate"
echo "  /root/ica.chain - Full chain (intermediate + root)"
echo "  /root/ica.key   - Intermediate CA private key"
