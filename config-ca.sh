#!/bin/bash
# filename - config-ca.sh
# version - 20250708-01
# description - Script to create a linux certificate authority
# restrictions - Script must be ran using sudo or sudo su
# Script will create a new 

# EDIT BELOW PARAMETERS TO MEET YOUR REQUIREMENTS

# BASIC HOST PARAMETERS
HOSTNAME="ca"
DOMAINNAME='localnet'
IFACE1="enp1s0"
IP1="10.5.5.70/24"
GW1="10.5.5.1"
NS1='10.5.5.60'
NS2='8.8.8.8'
DFN='/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg'    # Define name for cloud-init disablement file
NPF='/etc/netplan/01-netconfig.yaml'    # Define name for netplan config file

# CA SPECIFIC PARAMETERS
dir='/root/myCA'
C='US'
ST='Arizona'
L='Tombstone'
O='Company'
OU='Lab'

# DO NOT EDIT ANYTHING BELOW THIS LINE

# Test to see if script is running as root
if [ "$(id -u)" -eq 0 ]; then
    echo "You are running this script as root."
else
    echo "You are NOT running this script as root. Script will now terminate."
    read -p "Press enter to terminate the script"
    exit 1
fi

# Enable current user to use without security prompts
echo "Enabling $USER to run sudo without a password"
echo "$USER ALL=(ALL) NOPASSWD: ALL" | tee "/etc/sudoers.d/$USER"
chown root:root "/etc/sudoers.d/$USER"
chmod 440 "/etc/sudoers.d/$USER"

# Ensure openvswitch is installed
echo "apt intall -y openvswitch-switch"
apt install -y openvswitch-switch

# Ensure tree is installed
apt install -y tree

# Disable cloud-init network management
if test -d /etc/cloud ; then
  if ! test -f $DFN; then
      echo "network: {config: disabled}" | tee $DFN
      echo "Disabled cloud-init based network management to allow for use of netplan."  
      echo "After reboot, please rerun this script" 
      echo "Systen will reboot now"
      read
      # reboot
      init 6
  fi
fi

# set hostname
hostnamectl set-hostname $HOSTNAME --static

# Move existing netplan config files to /old/etc/netplan
mkdir -p /old/etc/netplan
mv -f /etc/netplan/* /old/etc/netplan/

# Create new netplan config (yaml) file
cat <<EOF > $NPF
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE1:
      dhcp4: no
      addresses: [$IP1]
      nameservers:
        addresses: [$NS1, $NS2] 
      routes:
        - to: 0.0.0.0/0
          via: $GW1
EOF
chown root:root $NPF
chmod 400 $NPF

# Apply new network configuration
netplan generate
netplan apply

# END OF NETWORK CONFIGURATION #
echo ""
echo "Network Configuration Modified - See below"
ip addr show $IFACE1
echo ''
read -p "If network settings are correct, press enter. Else press crtrl-c and fix script. : "

# START CONFIGURATION OF AN OPENSSL CERTIFICATE AUTHORITY

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
#
# CREATE CONFIG FILE FOR ROOT CERTIFICATE
ROOTCNF="$dir/openssl_root.cnf"

cat <<EOF > "$ROOTCNF"
[ ca ]                                                   # The default CA section
default_ca              = CA_default                     # The default CA name
[ CA_default ]                                           # Default settings for the CA
dir                     = $dir/rootCA                    # CA directory
certs                   = $dir/rootCA/certs              # Certificates directory
crl_dir                 = $dir/rootCA/crl                # CRL directory
new_certs_dir           = $dir/rootCA/newcerts           # New certificates directory
database                = $dir/rootCA/index.txt          # Certificate index file
serial                  = $dir/rootCA/serial             # Serial number file
RANDFILE                = $dir/rootCA/private/.rand      # Random number file
private_key             = $dir/rootCA/private/ca.key.pem # Root CA private key
certificate             = $dir/rootCA/certs/ca.cert.pem  # Root CA certificate
crl                     = $dir/rootCA/crl/ca.crl.pem     # Root CA CRL
crlnumber               = $dir/rootCA/crlnumber          # Root CA CRL number
crl_extensions          = crl_ext                        # CRL extensions
default_crl_days        = 30                             # Default CRL validity days
default_md              = sha256                         # Default message digest
preserve                = no                             # Preserve existing extensions
email_in_dn             = no                             # Exclude email from the DN
name_opt                = ca_default                     # Formatting options for names
cert_opt                = ca_default                     # Certificate output options
policy                  = policy_strict                  # Certificate policy
unique_subject          = no                             # Allow multiple certs with the same DN

[ policy_strict ]                                        # Policy for stricter validation
countryName             = match                          # Must match the issuer's country
stateOrProvinceName     = match                          # Must match the issuer's state
organizationName        = match                          # Must match the issuer's organization
organizationalUnitName  = optional                       # Organizational unit is optional
commonName              = supplied                       # Must provide a common name
emailAddress            = optional                       # Email address is optional

[ req ]                                                  # Request settings
default_bits            = 2048                           # Default key size
distinguished_name      = req_distinguished_name         # Default DN template
string_mask             = utf8only                       # UTF-8 encoding
default_md              = sha256                         # Default message digest
prompt                  = no                             # Non-interactive mode

[ req_distinguished_name ]                               # Template for the DN in the CSR
countryName             = Country Name (2 letter code)
stateOrProvinceName     = State or Province Name (full name)
localityName            = Locality Name (city)
0.organizationName      = Organization Name (company)
organizationalUnitName  = Organizational Unit Name (section)
commonName              = Common Name (your domain)
emailAddress            = Email Address

[ v3_ca ]                                                # Root CA certificate extensions
subjectKeyIdentifier    = hash                           # Subject key identifier
authorityKeyIdentifier  = keyid:always,issuer            # Authority key identifier
basicConstraints        = critical, CA:true              # Basic constraints for a CA
keyUsage                = critical, keyCertSign, cRLSign # Key usage for a CA

[ crl_ext ]                                              # CRL extensions
authorityKeyIdentifier  = keyid:always,issuer            # Authority key identifier

[ v3_intermediate_ca ]
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always,issuer
basicConstraints        = critical, CA:true, pathlen:0
keyUsage                = critical, digitalSignature, cRLSign, keyCertSign
EOF
echo ''
echo "Config file for root certificate created. See below"
echo ""
cat $ROOTCNF
echo ""
read -p "If configuration file is correct press ENTER, else press CRTL-C and fix script : "

# ROOT CA KEY AND CERTIFICATE GENERATION
echo ""
echo "GENERATING ROOT CA PRIVATE KEY"
openssl genrsa -out "$dir/rootCA/private/ca.key.pem" 4096
chmod 400 "$dir/rootCA/private/ca.key.pem"
echo ""
echo "Root certiicate private key created. See below."
echo ""
cat "$dir/rootCA/private/ca.key.pem"
echo ""
echo "SHOW CONTENTS OF PRIVATE KEY"
openssl rsa -noout -text -in "$dir/rootCA/private/ca.key.pem"
echo ""
read -p "If private key appears to be correct press enter, else press CRTL-C and fix script. : "
echo ""

echo "GENERATING ROOT CA PUBLIC CERTIFICATE"
openssl req -config "$ROOTCNF" -key "$dir/rootCA/private/ca.key.pem" -new -x509 -days 7300 -sha256 -extensions v3_ca -out "$dir/rootCA/certs/ca.cert.pem" -subj "/C=$C/ST=$ST/L=$L/O=$O/OU=$OU/CN=Root CA"
chmod 444 "$dir/rootCA/certs/ca.cert.pem"
echo ""
echo "SHOW CONTENT OF ROOT PUBLIC CERTIFICATE"
echo ""
openssl x509 -noout -text -in ~/myCA/rootCA/certs/ca.cert.pem
echo ""
read -p "If rooot ca public key appears to be correct press enter, else press CRTL-C and fix script. : "
echo ""

#
# INTERMEDIATE CA KEY AND CERTIFICATE GENERATION
INTERCNF="$dir/openssl_intermediate.cnf"

cat <<EOF > $INTERCNF
[ ca ]                                                   # The default CA section
default_ca              = CA_default                     # The default CA name

[ CA_default ]                                           # Default settings - intermediate CA
dir                     = $dir/intermediateCA            # Intermediate CA directory
certs                   = $dir/intermediateCA/certs      # Certificates directory
crl_dir                 = $dir/intermediateCA/crl        # CRL directory
new_certs_dir           = $dir/intermediateCA/newcerts   # New certificates directory
database                = $dir/intermediateCA/index.txt  # Certificate index file
serial                  = $dir/intermediateCA/serial     # Serial number file
RANDFILE                = $dir/intermediateCA/private/.rand                  # Random number file
private_key             = $dir/intermediateCA/private/intermediate.key.pem   # Intermediate CA private key
certificate             = $dir/intermediateCA/certs/intermediate.cert.pem    # Intermediate CA certificate
crl                     = $dir/intermediateCA/crl/intermediate.crl.pem       # Intermediate CA CRL
crlnumber               = $dir/intermediateCA/crlnumber     # Intermediate CA CRL number
crl_extensions          = crl_ext                           # CRL extensions
default_crl_days        = 30                                # Default CRL validity days
default_md              = sha256                            # Default message digest
preserve                = no                                # Preserve existing extensions
email_in_dn             = no                                # Exclude email from the DN
name_opt                = ca_default                        # Formatting options for names
cert_opt                = ca_default                        # Certificate output options
policy                  = policy_loose                      # Certificate policy

[ policy_loose ]                                            # Policy for less strict validation
countryName             = optional                          # Country is optional
stateOrProvinceName     = optional                          # State or province is optional
localityName            = optional                          # Locality is optional
organizationName        = optional                          # Organization is optional
organizationalUnitName  = optional                          # Organizational unit is optional
commonName              = supplied                          # Must provide a common name
emailAddress            = optional                          # Email address is optional

[ req ]                                                     # Request settings
default_bits            = 2048                              # Default key size
distinguished_name      = req_distinguished_name            # Default DN template
string_mask             = utf8only                          # UTF-8 encoding
default_md              = sha256                            # Default message digest
x509_extensions         = v3_intermediate_ca                # Extensions intermediate CA certificate

[ req_distinguished_name ]                                  # Template for the DN in the CSR
countryName             = Country Name (2 letter code)
stateOrProvinceName     = State or Province Name
localityName            = Locality Name
0.organizationName      = Organization Name
organizationalUnitName  = Organizational Unit Name
commonName              = Common Name
emailAddress            = Email Address

[ v3_intermediate_ca ]                                      # Intermediate CA certificate extensions
subjectKeyIdentifier    = hash                              # Subject key identifier
authorityKeyIdentifier  = keyid:always,issuer               # Authority key identifier
basicConstraints        = critical, CA:true, pathlen:0      # Basic constraints for a CA
keyUsage                = critical, digitalSignature, cRLSign, keyCertSign    # Key usage for a CA

[ crl_ext ]                                                 # CRL extensions
authorityKeyIdentifier  = keyid:always                      # Authority key identifier

[ server_cert ]                                             # Server certificate extensions
basicConstraints        = CA:FALSE                          # Not a CA certificate
nsCertType              = server                            # Server certificate type
keyUsage                = critical, digitalSignature, keyEncipherment  # Key usage for a server cert
extendedKeyUsage        = serverAuth                        # Extended key usage for server authentication purposes (e.g., TLS/SSL servers).
authorityKeyIdentifier  = keyid,issuer                      # Authority key identifier linking the certificate to the issuer's public key.
EOF
echo ''
echo "Config file for intermediate certificate created. See below"
echo ""
cat $INTERCNF
echo ""
read -p "If configuration file is correct press ENTER, else press CRTL-C and fix script : "

echo "GENERATING INTERMEDIATE CA PRIVATE KEY"
openssl genrsa -out "$dir/intermediateCA/private/intermediate.key.pem" 4096
chmod 400 "$dir/intermediateCA/private/intermediate.key.pem"
echo ""
echo "Intermediate certiicate private key created. See below."
echo ""
cat "$dir/intermediateCA/private/intermediate.key.pem"
echo ""
echo "SHOW CONTENTS OF PRIVATE KEY"
openssl rsa -noout -text -in "$dir/intermediateCA/private/intermediate.key.pem"
echo ""
read -p "If private key appears to be correct press enter, else press CRTL-C and fix script. : "
echo ""

echo "GENERATING CSR TO REQUEST INTERMEDIATE CA PUBLIC CERTIFICATE"
openssl req -config "$INTERCNF" -key "$dir/intermediateCA/private/intermediate.key.pem" -new -sha256 -out "$dir/intermediateCA/csr/intermediate.csr.pem" -subj "/C=$C/ST=$ST/L=$L/O=$O/OU=$OU/CN=Intermediate CA"

echo ""
echo "Certificate Service Request for Intermediate CA certificate generated, see below"
echo ""
cat "$dir/intermediateCA/csr/intermediate.csr.pem"
echo ""
read -p "If csr appears to be correct press enter, else press CRTL-C and fix script. : "
echo ""

echo "REQUESTING INTERMEDIATE CA PUBLIC CERTIFICATE USING CSR FILE"
openssl ca -config "$ROOTCNF" -extensions v3_intermediate_ca -days 3650 -notext -md sha256 -in "$dir/intermediateCA/csr/intermediate.csr.pem" -out "$dir/intermediateCA/certs/intermediate.cert.pem"
chmod 444 "$dir/intermediateCA/certs/intermediate.cert.pem"
echo ""
cat "$dir/intermediateCA/certs/intermediate.cert.pem"
echo ""
read -p "If cert appears to be correct press enter, else press CRTL-C and fix script. : "
echo ""



echo "VERIFYING CERTIFICATE FILE IS NOW LOCATED IN THE CA INDEX FILE"
echo "SHOULD RETURN A LINE INCLUDING"
echo "V 330503082700Z 1000 unknown /C=$C/ST=$ST/L=$L/O=$O/OU=$OU/CN=Intermediate CA"
echo ""
cat "$dir/rootCA/index.txt"
echo ""
read -p "If index data appears to be correct press enter, else press CRTL-C and fix script. : "
echo ""

echo "SHOWING CONTENT OF INTERMEDIATE CA PUBLIC CERTIFICATE"
openssl x509 -noout -text -in "$dir/intermediateCA/certs/intermediate.cert.pem"
echo ""
read -p "If cert contents appears to be correct press enter, else press CRTL-C and fix script. : "
echo ""

echo "VERIFYING INTERMEDIATE CERTIFICATE"
openssl verify -CAfile "$dir/rootCA/certs/ca.cert.pem" "$dir/intermediateCA/certs/intermediate.cert.pem"
echo ""
read -p "If cert verification appears to be correct press enter, else press CRTL-C and fix script. : "
echo ""

# CREATE TRUST CHAIN CERTIFICATE
echo "CREATING TRUST CHAIN FILE"
cat "$dir/intermediateCA/certs/intermediate.cert.pem" "$dir/rootCA/certs/ca.cert.pem" > "$dir/intermediateCA/certs/ca-chain.cert.pem"
echo ""
echo "Trust chain file contents displayed below"
echo ""
cat "$dir/intermediateCA/certs/ca-chain.cert.pem"
echo ""
read -p "If cert chain appears to be correct press enter, else press CRTL-C and fix script. : "
echo ""


echo "VERIFYING CERTIFICATE CHAIN FILE"
openssl verify -CAfile '$dir/intermediateCA/certs/ca-chain.cert.pem" "$dir/intermediateCA/certs/intermediate.cert.pem"



