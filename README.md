I did a full rebuild of the bash shell script that creates a standalone certificate authority on a linux os.

The new script, build-ca.sh, created the root and intermediate configuraiton files and builds out the root and intermediate ca (creates private key and public cert files for both).

The script has user configurable variables to defime C/ST/L/O/OU parameters that are needed to create the CA.

The defaults are C=US/ST=Arizona/L=Tombstone/O=Company/OU=Lab  

The script is intended to be ran as root. There is a check in the script that will cause it to abort if it is not ran as root. 

Prep linux 22.04 (ubuntu server), sign in and then
    $ sudo su
    # apt update
    # apt upgrade -y
    # copy build-ca.sh to the /root directory on a linux 22.04 server.
    # edit build-ca.sh  to set your counrty - state - city - organization - org unit - in these files
    # chmod +x build-ca.sh
    # ./build-ca.sh

The script runs with multiple check points that allow you to abort if ther eis a parameter or script error.

The other utility scripts in this repo help with creating certificates using this new CA. 

Results will be a CA you can use to issue SAN certificates. 

If you do not have a dns server in your lab, you can use the script "set-dns.sh" on the CA server and have a dual purpose machine.

I will post later script to generate SAN certiifcates.

These scripts are consolidated primarily from the work represented at the following URLs

https://www.golinuxcloud.com/openssl-create-certificate-chain-linux/

https://www.golinuxcloud.com/openssl-subject-alternative-name/

I recommend you open these links and verify my scripts before using them.

Contact data: mike.bomba@outlook.com
