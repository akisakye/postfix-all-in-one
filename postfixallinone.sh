#!/bin/sh
echo "This script will install postfix one in all. It's as is where is"
echo "Continue?"
read continue_install
if [ $continue_install = 'y' ]
then
echo "Installation will start now..."
echo "You will be asked to select various installation options"
sleep 2
echo "--------------------------------------------------------"
echo "Mail Server Section(Postfix, Dovecot)"
echo "--------------------------------------------------------"
echo "Do you want to install Postfix"
read postfix_install
echo "Do you want to install Dovecot"
read dovecot_install

mypass="123123321321"



apt-get update -y
export DEBIAN_FRONTEND=noninteractive
if [ $postfix_install = 'y' ]
then
apt-get install postfix postfix-mysql mysql-server mailutils -y
mysql -uroot mysql -e"update user set authentication_string=password('1111') where user='root';"
mysql -uroot mysql -e"create database post_virtual_db;"
mysql -uroot mysql -e"grant all on post_virtual_db.* to 'postman'@'localhost' identified by 'passo';"
sed -i 's/#submission/submission/g' /etc/postfix/master.cf
sed -i 's/#smtps/smtps/g' /etc/postfix/master.cf

echo "# Enabling tls please change cert and key below to reflect your environment" >> /etc/postfix/main.cf
postconf -e "smtp_tls_security_level = may"
postconf -e "smtp_tls_loglevel = 1"
postconf -e "smtpd_tls_loglevel = 1"
postconf -e "smtpd_tls_security_level = may"
postconf -e "smtpd_tls_auth_only = yes"
postconf -e "smtpd_tls_cert_file = /etc/ssl/certs/ssl-cert-snakeoil.pem"
postconf -e "smtpd_tls_key_file = /etc/ssl/private/ssl-cert-snakeoil.key"
postconf -e "smtpd_tls_received_header = yes"
postconf -e "smtpd_tls_session_cache_timeout = 3600s"
postconf -e "tls_random_source = dev:/dev/urandom"

echo "# HELO restrictions:" >> /etc/postfix/main.cf
postconf -e "smtpd_delay_reject = yes"
postconf -e "smtpd_helo_required = yes"
postconf -e "smtpd_helo_restrictions = permit_mynetworks permit_sasl_authenticated reject_non_fqdn_helo_hostname reject_invalid_helo_hostname permit"

else
echo "Skipping Postfix install"
fi;

if [ $dovecot_install = 'y' ]
then
apt-get install dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd dovecot-mysql dovecot-sieve dovecot-managesieved -y
rm -rf /etc/postfix/database && mkdir /etc/postfix/database
echo "#Dovecot auth for SMTP" >> /etc/postfix/main.cf

postconf -e "smtpd_sasl_type = dovecot"
postconf -e "smtpd_sasl_path = private/auth"
postconf -e "smtpd_sasl_auth_enable = yes"
postconf -e "smtpd_recipient_restrictions = permit_sasl_authenticated permit_mynetworks reject_unauth_destination"
postconf -e "mydestination = localhost"
postconf -e "virtual_transport = lmtp:unix:private/dovecot-lmtp"

echo "# virtual mailbox uid/gid" >> /etc/postfix/main.cf
postconf -e "virtual_uid_maps = static:3000"
postconf -e "virtual_gid_maps = static:3000"
postconf -e "virtual_alias_maps = mysql:/etc/postfix/database/virtual_alias_maps.cf"
postconf -e "virtual_mailbox_domains = mysql:/etc/postfix/database/virtual_domains_maps.cf"
postconf -e "virtual_mailbox_maps = mysql:/etc/postfix/database/virtual_mailbox_maps.cf"

printf "user = postman\n
password = passo\n
hosts = 127.0.0.1\n
dbname = post_virtual_db\n
query = SELECT goto FROM alias WHERE address = '%s' AND active = '1'" >> /etc/postfix/database/virtual_alias_maps.cf

printf "user = postman\n
password = passo\n
hosts = 127.0.0.1\n
dbname = post_virtual_db\n
query = SELECT domain FROM domain WHERE domain = '%s' AND backupmx = '0' AND active = '1'" >> /etc/postfix/database/virtual_domains_maps.cf

printf "user = postman\n
password = passo\n
hosts = 127.0.0.1\n
dbname = post_virtual_db\n
query = SELECT maildir FROM mailbox WHERE username = '%s' AND active = '1'" >> /etc/postfix/database/virtual_mailbox_maps.cf

groupadd -g 3000 vmail
useradd -g vmail -u 3000 vmail -d /var/vmail -m

echo "protocols = imap pop3 lmtp sieve" >> /etc/dovecot/dovecot.conf

sed -i 's/mail_location/#mail_location/g' /etc/dovecot/conf.d/10-mail.conf
echo "mail_location = maildir:/var/vmail/%d/%n" >> /etc/dovecot/conf.d/10-mail.conf

sed -i 's/auth_mechanisms/#auth_mechanisms/g' /etc/dovecot/conf.d/10-auth.conf
echo "auth_mechanisms = plain login" >> /etc/dovecot/conf.d/10-auth.conf
echo "disable_plaintext_auth = no" >> /etc/dovecot/conf.d/10-auth.conf
sed -i '/auth-system.conf.ext/d' /etc/dovecot/conf.d/10-auth.conf

echo "# Adding db auth" >> /etc/dovecot/conf.d/10-auth.conf
printf "passdb {\n
    driver = sql\n
    args = /etc/dovecot/dovecot-sql.conf.ext\n
}\n
userdb {\n
    driver = static\n
    args = uid=3000 gid=3000 home=/var/vmail/%d/%n allow_all_users=yes\n
}\n " >> /etc/dovecot/conf.d/10-auth.conf

printf "driver = mysql\n
connect = host=127.0.0.1 dbname=post_virtual_db user=postman password=passo\n
password_query = SELECT username AS user, password, homedir AS userdb_home, uid AS userdb_uid, gid AS userdb_gid FROM mailbox WHERE username = '%u' iterate_query = SELECT username AS user FROM mailbox" >> /etc/dovecot/dovecot-sql.conf.ext

mv /etc/dovecot/conf.d/10-master.conf /etc/dovecot/conf.d/10-master.conf.old

printf "service imap-login { \n
  inet_listener imap {\n
  }\n
  inet_listener imaps {\n
  }\n
  
}\n

service pop3-login {\n
  inet_listener pop3 {\n
  }\n
  inet_listener pop3s {\n
  }\n
}\n

service lmtp {\n
 unix_listener /var/spool/postfix/private/dovecot-lmtp {\n
   mode = 0600\n
   user = postfix\n
   group = postfix\n
  }\n
}\n
service imap {\n
}\n

service pop3 {\n
}\n

service auth {\n
 unix_listener /var/spool/postfix/private/auth {\n
    mode = 0666\n
    user = postfix\n
    group = postfix\n
  }\n
  unix_listener auth-userdb {\n
    mode = 0600\n
    user = vmail\n
  }\n

  user = dovecot\n
}\n

service auth-worker {\n
  user = vmail\n
}\n

service dict {\n
  unix_listener dict {\n
  }\n
}" >> /etc/dovecot/conf.d/10-master.conf

/etc/init.d/postfix restart
/etc/init.d/dovecot restart


else
echo "Skipping Dovecot install"
fi;





else
echo "No Changes have been made to the system!"
fi;
