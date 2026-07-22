# Private Lab CA Toolkit

A set of bash scripts to build and operate a private Certificate Authority on Linux for lab environments.

## Features

- Root CA + Intermediate CA hierarchy (proper chain of trust)
- TLS server certificates with Subject Alternative Names (SAN)
- Multiple workflows: all-in-one, CSR-only, or sign-existing-CSR
- Shared configuration via `ca-vars.conf` (prompts for missing values, saves for reuse)
- Entity identity certificates (planned)

## File Layout

```
/root/
├── ca-vars.conf              # Shared variables (auto-created on first run)
├── build-ca.sh               # Creates Root CA + Intermediate CA hierarchy
├── gen-crt-and-key.sh        # Generates key + CSR + signed cert + PFX (all-in-one)
├── gen-csr.sh                # Generates key + CSR only (for external signing)
├── gen-crt-from-csr.sh       # Signs an existing CSR into a certificate
└── myCA/                     # CA hierarchy (created by build-ca.sh)
    ├── openssl_root.cnf
    ├── openssl_intermediate.cnf
    ├── rootCA/
    │   ├── certs/ca.cert.pem
    │   ├── private/ca.key.pem
    │   ├── crl/
    │   ├── newcerts/
    │   ├── index.txt
    │   └── serial
    └── intermediateCA/
        ├── certs/
        │   ├── intermediate.cert.pem
        │   └── intermediate.chain.pem
        ├── private/intermediate.key.pem
        ├── crl/
        ├── newcerts/
        ├── index.txt
        └── serial
```

## Quick Start

### Prerequisites

- Linux (tested on Ubuntu 22.04 / Linux Mint 22)
- OpenSSL
- Run all scripts as root

```bash
sudo su
apt update && apt upgrade -y
```

### 1. Build the CA (one-time setup)

```bash
cp build-ca.sh gen-crt-and-key.sh gen-csr.sh gen-crt-from-csr.sh /root/
chmod +x /root/*.sh
bash /root/build-ca.sh
```

On first run, you will be prompted for:
- `CA_DIR` - where to store the CA (default: `/root/myCA`)
- `C`, `ST`, `L`, `O`, `OU` - certificate subject fields

Values are saved to `/root/ca-vars.conf` for all future scripts.

### 2. Issue a TLS Certificate (key + cert + PFX)

```bash
bash /root/gen-crt-and-key.sh
```

Prompts for: file prefix, FQDN, hostname, IP addresses, password.

Produces in the current directory:
- `<name>.key` - private key
- `<name>.crt` - signed certificate
- `<name>.pfx` - PKCS#12 bundle
- `<name>_ica.chain` - CA chain file
- `<name>_ica.crt` - Intermediate CA cert
- `<name>_rca.crt` - Root CA cert
- `<name>_certs.zip` - encrypted archive of all files

### 3. Generate a CSR Only (for external signing workflow)

```bash
bash /root/gen-csr.sh
```

Prompts for: FQDN, DNS names, IP addresses.

Produces:
- `<name>.key` - private key
- `<name>.csr` - certificate signing request
- `<name>.cnf` - OpenSSL config used

### 4. Sign an Existing CSR

```bash
bash /root/gen-crt-from-csr.sh [path/to/file.csr]
```

Extracts SANs from the CSR and issues a signed certificate. If no argument is given, prompts for the CSR filename.

Produces:
- `<name>.crt` - signed certificate
- `<name>.chain` - CA chain file

## Configuration

All shared variables are stored in `/root/ca-vars.conf`:

```
CA_DIR='/root/myCA'
C='US'
ST='Arizona'
L='Tombstone'
O='lab'
OU='demo'
```

- Delete a value to be prompted for it on next run.
- Delete the entire file to reset all defaults.

## Deploying to a New Host

```bash
scp /root/build-ca.sh /root/gen-crt-and-key.sh /root/gen-csr.sh \
    /root/gen-crt-from-csr.sh root@new-host:/root/
ssh root@new-host 'bash /root/build-ca.sh'
```

## Certificate Validity

| Certificate | Validity |
|-------------|----------|
| Root CA | 20 years (7300 days) |
| Intermediate CA | 10 years (3650 days) |
| Server certs | 1 year (365 days) |

## Trusting the CA on Clients

### Linux (NSS/browser)

```bash
certutil -d sql:$HOME/.pki/nssdb -A -t "C,," -n lab_root_ca -i /root/myCA/rootCA/certs/ca.cert.pem
certutil -d sql:$HOME/.pki/nssdb -A -t "C,," -n lab_intermediate_ca -i /root/myCA/intermediateCA/certs/intermediate.cert.pem
```

### Linux (system-wide)

```bash
cp /root/myCA/rootCA/certs/ca.cert.pem /usr/local/share/ca-certificates/lab-root-ca.crt
cp /root/myCA/intermediateCA/certs/intermediate.cert.pem /usr/local/share/ca-certificates/lab-intermediate-ca.crt
update-ca-certificates
```

### Windows

Import the Root CA and Intermediate CA `.crt` files into the Trusted Root / Intermediate certificate stores via `certmgr.msc` or GPO.

## Planned Features

- Entity identity certificates (client auth / mTLS)
- CRL generation and distribution
- OCSP responder configuration

## References

These scripts are consolidated primarily from the work represented at the following URLs:

- https://www.golinuxcloud.com/openssl-create-certificate-chain-linux/
- https://www.golinuxcloud.com/openssl-subject-alternative-name/

## Contact

mike.bomba@outlook.com
