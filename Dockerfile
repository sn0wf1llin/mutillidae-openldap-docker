# ############################################################################################################################################
# Dockerfile Mutillidae + OpenLDAP
#
# docker network create --attachable --driver=bridge --subnet=173.17.0.0/16 --ip-range=173.17.0.2/24 --gateway=173.17.0.1 my-attachable-network
# docker build --build-arg MYSQL_DATABASE_USERNAME="admin" --build-arg MYSQL_DATABASE_PASSWORD="admin" . -t mutillidae:2.7.11
# docker run --network=my-attachable-network --name mutillidae-last mutillidae:2.7.11
# #############################################################################################################################################

FROM	debian:stretch
MAINTAINER	nocat <nocat@nomail.not>

ARG	MYSQL_DATABASE_PASSWORD="mutillidae"
ARG	LDAP_OPENLDAP_GID=1111
ARG	LDAP_OPENLDAP_UID=1111

ENV	DEBIAN_FRONTEND		noninteractive
ENV	LDAP_DEBUG_LEVEL	235

RUN	apt update && \
	apt install -y apache2 libapache2-mod-php php php-mysql php-curl php-xml mysql-server \
	php-mbstring php7.0-ldap wget unzip dnsutils curl nano \
	bash vim lsof procps net-tools netcat git tcpdump && \
	rm -rf /var/lib/apt/lists/* && \
    	a2enmod rewrite && \
			service apache2 restart && \
    	VAR_WWW_LINE=$(grep -n '<Directory /var/www/>' /etc/apache2/apache2.conf | cut -f1 -d:) && \
    	VAR_WWW_END_LINE=$(tail -n +$VAR_WWW_LINE /etc/apache2/apache2.conf | grep -n '</Directory>' | head -n 1 | cut -f1 -d:) && \
    	REPLACE_ALLOW_OVERRIDE_LINE=$(($(tail -n +$VAR_WWW_LINE /etc/apache2/apache2.conf | head -n "$VAR_WWW_END_LINE" | grep -n AllowOverride | cut -f1 -d:) + $VAR_WWW_LINE - 1)) && \
    	sed -i "${REPLACE_ALLOW_OVERRIDE_LINE}s/None/All/" /etc/apache2/apache2.conf

RUN	service mysql start && \
    	while [ ! -S /var/run/mysqld/mysqld.sock ]; do sleep 1; done && \
    	sleep 5 && \
    	echo "update user set authentication_string=PASSWORD('${MYSQL_DATABASE_PASSWORD}') where user='root';" | mysql -u root -v mysql && \
    	echo "update user set plugin='mysql_native_pass
# ##############################
# LDAP #########################
# ##############################word' where user='root';" | mysql -u root -v mysql && \
    	service mysql stop && \
    	sed -i 's/^error_reporting.*/error_reporting = E_ALL/g' /etc/php/7.0/apache2/php.ini && \
    	sed -i 's/^display_errors.*/display_errors = On/g' /etc/php/7.0/apache2/php.ini

RUN	mkdir -p /var/www/html && \
	cd /tmp && \
	git clone https://github.com/webpwnized/mutillidae.git && \
	mv /tmp/mutillidae /var/www/html/

RUN	sed -i 's/^Deny from all/Allow from all/g' /var/www/html/mutillidae/.htaccess

# ##############################
# LDAP #########################
# ##############################

RUN	if [ -z "${LDAP_OPENLDAP_GID}" ]; then groupadd -r openldap; else groupadd -r -g ${LDAP_OPENLDAP_GID} openldap; fi
RUN	if [ -z "${LDAP_OPENLDAP_UID}" ]; then useradd -r -g openldap openldap; else useradd -r -g openldap -u ${LDAP_OPENLDAP_UID} openldap; fi

RUN	apt-get update && \
	apt-get install -y --no-install-recommends \
	ldap-utils \
	slapd expect

RUN	printf "#\n# LDAP Defaults\n#\n\n# See ldap.conf(5) for details\n# This file should be world readable but not world writable.\n\nBASE   dc=mutillidae,dc=local\nURI    ldaps://ldap.mutillidae.local\n\n#SIZELIMIT      12\n#TIMELIMIT      15\n#DEREF          never\n\n# TLS certificates (needed for GnuTLS)\nTLS_CACERT      /etc/ssl/certs/ca-certificates.crt" >  /etc/ldap/ldap.conf

# Automatization of dpkg-reconfigure
RUN	echo '#!/usr/bin/expect' > /dpkg-reconfigure-expect.script && \
		printf "\nspawn dpkg-reconfigure slapd -freadline\nexpect \"Omit OpenLDAP server configuration?\"\nsend \"no\\\r\"" >> /dpkg-reconfigure-expect.script && \
		printf "\nexpect \"DNS domain name: \"\nsend \"mutillidae.local\\r\"\n\nexpect \"Organization name: \"\nsend \"mutillidae\\\r\"" >> /dpkg-reconfigure-expect.script && \
		printf "\nexpect \"Administrator password: \"\nsend \"mutillidae\\\r\"" >> /dpkg-reconfigure-expect.script && \
		printf "\nexpect \"Confirm password: \"send \"mutillidae\\\r\"" >> /dpkg-reconfigure-expect.script && \
		printf "\nexpect \"Database backend to use: \"send \"3\\\r\"" >> /dpkg-reconfigure-expect.script && \
		printf "\nexpect \"Do you want the database to be removed when slapd is purged?\"send \"yes\\\r\"" >> /dpkg-reconfigure-expect.script && \
		printf "\nexpect \"Move old database?\"send \"no\\\r\"" >> /dpkg-reconfigure-expect.script && \
		printf "\nexpect eof\"" >> /dpkg-reconfigure-expect.script

RUN service slapd start && \
		chmod +x /dpkg-reconfigure-expect.script && \
		/dpkg-reconfigure-expect.script

RUN	TEST_LDAP=`ldapsearch -x -b 'dc=mutillidae,dc=local' "objectClass=rooms"`; \
		if [ -z `echo $TEST_LDAP | grep Success` ] ; then \
			echo "[FAIL] LDAP test output result $TEST_LDAP"; \
			else echo ""; \
			echo "[OK] LDAP test output: $TEST_LDAP"; fi ;

# ##############################
# phpLDAPadmin #################
# ##############################
# sed -i "s@// $servers->setValue('server','host','127.0.0.1');@$servers->setValue('server','host','127.0.0.1');@" config/config.php && \
RUN	cd /var/www/html && \
		git clone https://github.com/leenooks/phpLDAPadmin.git && \
		cd phpLDAPadmin && \
		cp config/config.php.example config/config.php && \
		sed -i '162i$config->custom->appearance['hide_template_warning'] = true;' config/config.php && \
		sed -i 's/My LDAP Server/mutillidae LDAP Server/' config/config.php && \
		sed -i "301a\$servers->setValue('server','base',array('dc=mutillidae,dc=local'));" config/config.php && \
		sed -i "328a\$servers->setValue('login','bind_id','cn=admin,dc=mutillidae,dc=local');" config/config.php && \
		service apache2 restart		

# ##############################

EXPOSE	80 3306 389 636 22

CMD ["bash", "-c", "service mysql start && service apache2 start && sleep infinity & wait"]
