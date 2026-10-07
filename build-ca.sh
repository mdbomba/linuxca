#!/bin/bash
# filename - build-ca.sh
# version - 20260919-01
# description - Script to create a linux Root and Intermediate certificate authority
# restrictions - Script must be run as root
# CA hierarchy is created in the location selected at runtime.

set -euo pipefail

umask 077

PUBLIC_CA_DIR="/opt/myCA/public"
dir="/root/myCA"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root."
    exit 1
fi

prompt_var() {
    local var_name="$1"
    local prompt_msg="$2"
    local current_val="${!var_name:-}"

    if [[ -z "$current_val" ]]; then
        read -r -p "$prompt_msg" "$var_name"
    fi
}

# Determine whether a complete CA hierarchy already exists
complete_ca=1
for f in \
    "$dir/rootCA/certs/ca.cert.pem" \
    "$dir/rootCA/private/ca.key.pem" \
    "$dir/intermediateCA/certs/intermediate.cert.pem" \
    "$dir/intermediateCA/private/intermediate.key.pem"; do
    [[ -f "$f" ]] || complete_ca=0
done

if [[ -d "$dir" && "$complete_ca" -eq 1 ]]; then
    printf 'Complete CA hierarchy found at %s. Skipping CA creation.\n' "$dir"
    exit 0
fi

if [[ -d "$dir" && "$complete_ca" -eq 0 ]]; then
    printf 'WARNING: Incomplete/broken CA hierarchy found at %s.\n' "$dir"
    printf 'One or more required files are missing:\n'
    printf '  %s\n' \
        "$dir/rootCA/certs/ca.cert.pem" \
        "$dir/rootCA/private/ca.key.pem" \
        "$dir/intermediateCA/certs/intermediate.cert.pem" \
        "$dir/intermediateCA/private/intermediate.key.pem"
    printf '\n'
    printf 'Rebuilding requires DELETING all of %s (and stale copies in %s).\n' "$dir" "$PUBLIC_CA_DIR"
    printf 'This is PERMANENT - any certificates already issued become invalid.\n'
    read -r -p "Type 'wipe' to delete and rebuild (anything else aborts): " confirm
    if [[ "$confirm" == "wipe" ]]; then
        printf 'Removing %s and %s ...\n' "$dir" "$PUBLIC_CA_DIR"
        rm -rf "$dir"
        rm -rf "$PUBLIC_CA_DIR"
    else
        printf 'Aborted. Remove/fix %s manually and re-run.\n' "$dir"
        exit 1
    fi
fi

prompt_var C "Enter 2 letter Country Code [US]: "
C="${C:-US}"
prompt_var ST "Enter State or Province [AZ]: "
ST="${ST:-AZ}"
prompt_var L "Enter Locality Name [Cochise]: "
L="${L:-Cochise}"
prompt_var O "Enter Organization Name [Demo]: "
O="${O:-Demo}"
prompt_var OU "Enter Organizational Unit Name [Lab]: "
OU="${OU:-Lab}"


# Ensure tree is installed
if ! command -v tree > /dev/null; then
    apt install -y -qq tree
fi

# CREATE DIRECTORY AND DEFAULT FILE STRUCTURES
mkdir -p "$dir/rootCA"/{certs,crl,newcerts,private,csr}
mkdir -p "$dir/intermediateCA"/{certs,crl,newcerts,private,csr}
echo 1000 > "$dir/rootCA/serial"
echo 1000 > "$dir/intermediateCA/serial"
echo 0100 > "$dir/rootCA/crlnumber" 
echo 0100 > "$dir/intermediateCA/crlnumber"
touch "$dir/rootCA/index.txt"
touch "$dir/intermediateCA/index.txt"

printf '\n'
printf 'Directory structure for CA created. See below\n'
tree "$dir"
printf '\n'

read -r -p "If directory structure is correct, press enter, else press CTRL-C and fix script. : " _

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

printf '\n'
printf 'Config file for root certificate created. See below\n'
printf '\n'
cat "$ROOTCNF"
printf '\n'
read -r -p "If configuration file is correct press ENTER, else press CTRL-C and fix script : " _

# ROOT CA KEY AND CERTIFICATE GENERATION
printf '\n'
printf 'GENERATING ROOT CA PRIVATE KEY\n'
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$dir/rootCA/private/ca.key.pem"
chmod 400 "$dir/rootCA/private/ca.key.pem"
printf '\n'
printf 'Root CA private key created.\n'
printf '\n'
printf 'CHECKING ROOT CA PRIVATE KEY\n'
openssl rsa -check -noout -in "$dir/rootCA/private/ca.key.pem"
printf '\n'
read -r -p "If private key appears to be correct press enter, else press CTRL-C and fix script. : " _
printf '\n'

printf 'GENERATING ROOT CA PUBLIC CERTIFICATE\n'
openssl req -config "$ROOTCNF" -key "$dir/rootCA/private/ca.key.pem" -new -x509 -days 7300 -sha256 -extensions v3_ca -out "$dir/rootCA/certs/ca.cert.pem" -subj "/C=$C/ST=$ST/L=$L/O=$O/OU=$OU/CN=Root CA"
chmod 444 "$dir/rootCA/certs/ca.cert.pem"
printf '\n'
printf 'SHOW CONTENT OF ROOT PUBLIC CERTIFICATE\n'
printf '\n'
openssl x509 -noout -text -in "$dir/rootCA/certs/ca.cert.pem"
printf '\n'
read -r -p "If root CA public certificate appears to be correct press enter, else press CTRL-C and fix script. : " _
printf '\n'

# INTERMEDIATE CA KEY AND CERTIFICATE GENERATION
INTERCNF="$dir/openssl_intermediate.cnf"

cat <<EOF > "$INTERCNF"
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

printf '\n'
printf 'Config file for intermediate certificate created. See below\n'
printf '\n'
cat "$INTERCNF"
printf '\n'
read -r -p "If configuration file is correct press ENTER, else press CTRL-C and fix script : " _

printf 'GENERATING INTERMEDIATE CA PRIVATE KEY\n'
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$dir/intermediateCA/private/intermediate.key.pem"
chmod 400 "$dir/intermediateCA/private/intermediate.key.pem"
printf '\n'
printf 'Intermediate CA private key created.\n'
printf '\n'
printf 'CHECKING INTERMEDIATE CA PRIVATE KEY\n'
openssl rsa -check -noout -in "$dir/intermediateCA/private/intermediate.key.pem"
printf '\n'
read -r -p "If private key appears to be correct press enter, else press CTRL-C and fix script. : " _
printf '\n'

printf 'GENERATING CSR TO REQUEST INTERMEDIATE CA PUBLIC CERTIFICATE\n'
openssl req -config "$INTERCNF" -key "$dir/intermediateCA/private/intermediate.key.pem" -new -sha256 -out "$dir/intermediateCA/csr/intermediate.csr.pem" -subj "/C=$C/ST=$ST/L=$L/O=$O/OU=$OU/CN=Intermediate CA"

printf '\n'
printf 'Certificate Signing Request for Intermediate CA certificate generated, see below\n'
printf '\n'
cat "$dir/intermediateCA/csr/intermediate.csr.pem"
printf '\n'
read -r -p "If CSR appears to be correct press enter, else press CTRL-C and fix script. : " _
printf '\n'

printf 'REQUESTING INTERMEDIATE CA PUBLIC CERTIFICATE USING CSR FILE\n'
openssl ca -config "$ROOTCNF" -batch -extensions v3_intermediate_ca -days 3650 -notext -md sha256 -in "$dir/intermediateCA/csr/intermediate.csr.pem" -out "$dir/intermediateCA/certs/intermediate.cert.pem"
chmod 444 "$dir/intermediateCA/certs/intermediate.cert.pem"
printf '\n'
cat "$dir/intermediateCA/certs/intermediate.cert.pem"
printf '\n'
read -r -p "If cert appears to be correct press enter, else press CTRL-C and fix script. : " _
printf '\n'

printf 'VERIFYING CERTIFICATE FILE IS NOW LOCATED IN THE CA INDEX FILE\n'
printf '\n'
cat "$dir/rootCA/index.txt"
printf '\n'
read -r -p "If index data appears to be correct press enter, else press CTRL-C and fix script. : " _
printf '\n'

printf 'SHOWING CONTENT OF INTERMEDIATE CA PUBLIC CERTIFICATE\n'
openssl x509 -noout -text -in "$dir/intermediateCA/certs/intermediate.cert.pem"
printf '\n'
read -r -p "If cert contents appear to be correct press enter, else press CTRL-C and fix script. : " _
printf '\n'

printf 'VERIFYING INTERMEDIATE CERTIFICATE\n'
openssl verify -CAfile "$dir/rootCA/certs/ca.cert.pem" "$dir/intermediateCA/certs/intermediate.cert.pem"
printf '\n'
read -r -p "If cert verification appears to be correct press enter, else press CTRL-C and fix script. : " _
printf '\n'

# CREATE TRUST CHAIN CERTIFICATE
printf 'CREATING TRUST CHAIN FILE\n'
cat "$dir/intermediateCA/certs/intermediate.cert.pem" "$dir/rootCA/certs/ca.cert.pem" > "$dir/intermediateCA/certs/intermediate.chain.pem"
printf '\n'
printf 'Trust chain file contents displayed below\n'
printf '\n'
cat "$dir/intermediateCA/certs/intermediate.chain.pem"
printf '\n'
read -r -p "If cert chain appears to be correct press enter, else press CTRL-C and fix script. : " _
printf '\n'

printf 'VERIFYING CERTIFICATE CHAIN FILE\n'
openssl verify -CAfile "$dir/rootCA/certs/ca.cert.pem" "$dir/intermediateCA/certs/intermediate.cert.pem"

# Create safe location to collect ica, rca and chain certs
mkdir -p "$PUBLIC_CA_DIR"
chown root:root /opt/myCA "$PUBLIC_CA_DIR"
chmod 0755 /opt/myCA "$PUBLIC_CA_DIR"

# COPY CONVENIENCE FILES TO /opt/myCA/public
install -o root -g root -m 0444 "$dir/intermediateCA/certs/intermediate.cert.pem" "$PUBLIC_CA_DIR/ica.crt"
install -o root -g root -m 0444 "$dir/rootCA/certs/ca.cert.pem" "$PUBLIC_CA_DIR/rca.crt"
cat "$PUBLIC_CA_DIR/ica.crt" "$PUBLIC_CA_DIR/rca.crt" > "$PUBLIC_CA_DIR/chain.crt"
chown root:root "$PUBLIC_CA_DIR/chain.crt"
chmod 0644 "$PUBLIC_CA_DIR/chain.crt"

printf '\n'
printf 'CA build complete. Convenience copies placed in %s/:\n' "$PUBLIC_CA_DIR"
printf '  rca.crt   -  Root CA certificate\n'
printf '  ica.crt   -  Intermediate CA certificate\n'
printf '  chain.crt -  Full chain (intermediate + root)\n'
