There is certificate (Subject) data located in openssl_intermediate.cnf and in set-ca.sh. If you want to change the certificate Subject info, you need to edit both.

Steps to get the CA up and running

    Prep linux 22.04 (ubuntu server), sign in and then
    $ sudo su
    # copy set-ca.sh, openssl_root.cnf and openssl_intermediate.cnf to the /root directory on a linux 22.04 server.
    # edit set-ca.sh and openssl_intermediate.cnf to personalize CA (set your counrty - state - city - organization - org unit - in these files)
    # chmod +x set-ca.sh
    # ./set-ca.sh
Results will be a CA you can use to issue SAN certificates. 

I will post later script to generate SAN certiifcates.

These scripts are consolidated primarily from the work represented at the following URLs

https://www.golinuxcloud.com/openssl-create-certificate-chain-linux/

https://www.golinuxcloud.com/openssl-subject-alternative-name/

I recommend you open these links and verify my scripts before using them.

Contact data: mike.bomba@outlook.com
