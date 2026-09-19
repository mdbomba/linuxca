# Private Lab CA Toolkit

A collection of bash scripts to build and operate a private Certificate Authority (CA) for lab environments, backed by a Root CA + Intermediate CA hierarchy and TLS server certificates with Subject Alternative Names (SAN).

Current version: **20260919-01**

## Requirements

- Linux (tested on Ubuntu 22.04 / Linux Mint 22)
- OpenSSL 3.x (`openssl`), `tree`, `zip`
- Scripts needing CA access run privileged where required (see table below)
- `sudo` rights for the current user for signing scripts

## Scripts

| Script | Must run as | Purpose |
|--------|-------------|---------|
| `build-ca.sh` | root | One-time CA build: Root CA + Intermediate CA hierarchy |
| `gen-csr.sh` | regular user | Generate a private key + CSR with SANs (no CA access) |
| `gen-crt-and-key.sh` | regular user | All-in-one: key + CSR + signed cert + chain + PFX + ZIP |
| `gen-crt-from-csr.sh` | regular user | Sign an existing CSR (extracts CN + SANs from it) |

All signing actions (those that read the CA private key) run under `sudo`; everything else runs as the invoking user.

## CA layout

The CA is created under `/root/myCA`. Convenience copies of the CA certificates are placed in `/opt/myCA/public`.

```
/root/myCA/
├── openssl_root.cnf              # Root CA openssl config
├── openssl_intermediate.cnf      # Intermediate CA openssl config
├── rootCA/
│   ├── certs/ca.cert.pem         # Root CA certificate
│   ├── private/ca.key.pem        # Root CA private key (root-only)
│   ├── crl/ newcerts/ csr/
│   ├── index.txt                 # Issued-certificate database
│   └── serial crlnumber
└── intermediateCA/
    ├── certs/
    │   ├── intermediate.cert.pem # Intermediate CA certificate
    │   └── intermediate.chain.pem# Chain (intermediate + root)
    ├── private/intermediate.key.pem  # Intermediate CA private key (root-only)
    ├── crl/ newcerts/ csr/
    ├── index.txt
    └── serial crlnumber

/opt/myCA/public/                 # World-readable convenience copies
├── rca.crt                       # Root CA certificate
├── ica.crt                       # Intermediate CA certificate
└── chain.crt                     # Full chain (intermediate + root)
```

## 1. Build the CA (one-time, as root)

```bash
sudo su
cp build-ca.sh gen-csr.sh gen-crt-and-key.sh gen-crt-from-csr.sh /root/
chmod +x /root/*.sh
bash /root/build-ca.sh
```

What it does:

- Prompts for the subject fields `C` `ST` `L` `O` `OU` (defaults: US / AZ / Cochise / Lab / Home).
- Installs `tree` if missing, then creates the directory skeleton and OpenSSL configs. Each generated artifact is displayed and requires pressing Enter (or Ctrl-C to abort).
- Generates the Root CA key (RSA 4096) and self-signed certificate (7300 days / 20 years).
- Generates the Intermediate CA key (RSA 4096), CSR, and issues the Intermediate CA certificate (3650 days / 10 years, `pathlen:0`).
- Verifies the chain and writes `rca.crt` / `ica.crt` / `chain.crt` to `/opt/myCA/public`.

Re-run behavior:

- If a **complete** CA already exists (root + intermediate key/cert all present), the script reports this and exits without prompting.
- If an **incomplete/broken** hierarchy is found (e.g. an interrupted build), it warns and offers to wipe and rebuild — you must type `wipe` to delete `/root/myCA` and `/opt/myCA/public` and start fresh. Any certificate previously issued by that CA becomes invalid.

## 2. All-in-one: key + CSR + signed cert + PFX + ZIP

```bash
bash /root/gen-crt-and-key.sh
```

Prompts for: archive/PFX password, subject fields, file name prefix, FQDN/CN, short hostname, primary IPv4 (validated), optional secondary IP.

Produces in the current directory (`Name` = prefix, default `chef360`):

- `Name.key` / `Name.csr` / `Name.cnf` — private key (RSA 2048), CSR, openssl config
- `Name.crt` — signed server certificate (365 days)
- `Name_chain.crt` — CA chain file
- `Name_ica.crt` / `Name_rca.crt` — convenience copies of the CA certs
- `Name.pfx` — PKCS#12 bundle (password protected)
- `Name_certs.zip` — encrypted ZIP of all of the above (same password)

## 3. CSR only (key + CSR, no CA access)

```bash
bash /root/gen-csr.sh
```

Prompts for subject fields, prefix, FQDN, hostname, and IP addresses. Produces `Name.key`, `Name.csr`, `Name.cnf` (RSA 2048). Use `gen-crt-from-csr.sh` to sign it.

## 4. Sign an existing CSR

```bash
bash /root/gen-crt-from-csr.sh [path/to/file.csr]
```

Reads the CN and Subject Alternative Names directly from the CSR and issues a certificate (365 days). Produces `<base>.crt`, `<base>.cfg`, and `<base>_chain.crt`. If the CSR lacks a CN or any SANs, the script aborts.

## Certificate validity

| Certificate | Validity |
|-------------|----------|
| Root CA | 20 years (7300 days) |
| Intermediate CA | 10 years (3650 days) |
| Server certificates | 1 year (365 days) |

## How signing and serials work

- `build-ca.sh` issues the intermediate certificate through `openssl ca`, using the Root CA's `index.txt` / `serial` database.
- The signing scripts (`gen-crt-and-key.sh`, `gen-crt-from-csr.sh`) sign leaf certificates with `openssl x509 -req -CAcreateserial`. The serial file is maintained as `intermediate.cert.pem.srl`, stored next to the real intermediate certificate under `/root/myCA/intermediateCA/certs/`.

## Security notes

- CA private keys are **unencrypted** and protected only by the filesystem: the scripts run under `umask 077`, so everything under `/root/myCA` is root-only, and keys are `chmod 400`.
- Access to CA material on the build host is effectively restricted to `root`.

## Trusting the CA on clients

### Linux (browser / NSS)

```bash
certutil -d sql:$HOME/.pki/nssdb -A -t "C,," -n lab_root_ca -i /opt/myCA/public/rca.crt
certutil -d sql:$HOME/.pki/nssdb -A -t "C,," -n lab_intermediate_ca -i /opt/myCA/public/ica.crt
```

### Linux (system-wide)

```bash
cp /opt/myCA/public/rca.crt /usr/local/share/ca-certificates/lab-root-ca.crt
cp /opt/myCA/public/ica.crt /usr/local/share/ca-certificates/lab-intermediate-ca.crt
update-ca-certificates
```

### Windows

Import `rca.crt` and `ica.crt` into the Trusted Root / Intermediate certificate stores via `certmgr.msc` or GPO.

## Deploying to a new host

```bash
scp /root/build-ca.sh /root/gen-csr.sh /root/gen-crt-and-key.sh \
    /root/gen-crt-from-csr.sh root@new-host:/root/
ssh root@new-host 'bash /root/build-ca.sh'
```

## References

- https://www.golinuxcloud.com/openssl-create-certificate-chain-linux/
- https://www.golinuxcloud.com/openssl-subject-alternative-name/

## Contact

mike.bomba@outlook.com