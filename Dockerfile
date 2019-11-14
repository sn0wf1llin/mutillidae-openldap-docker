# ############################################################################################################################################
# Dockerfile Mutillidae + OpenLDAP
#
# docker network create --attachable --driver=bridge --subnet=173.17.0.0/16 --ip-range=173.17.0.2/24 --gateway=173.17.0.1 my-attachable-network
# docker build --build-arg MYSQL_DATABASE_USERNAME="admin" --build-arg MYSQL_DATABASE_PASSWORD="admin" . -t mutillidae:2.7.11
# docker run --network=my-attachable-network --name mutillidae-last mutillidae:2.7.11
# #############################################################################################################################################

FROM				debian:stretch
MAINTAINER	nocat <nocat@nomail.not>

ARG		MYSQL_DATABASE_PASSWORD="mutillidae"
ARG		LDAP_PASSWORD="mutillidae"
ARG		LDAP_OPENLDAP_GID=1111
ARG		LDAP_OPENLDAP_UID=1111
ARG		LDAP_OPENLDAP_USER="openldap"
ARG		LDAP_OPENLDAP_GROUP="openldap"

ENV		DEBIAN_FRONTEND	noninteractive
ENV		LDAP_DEBUG_LEVEL 235

RUN		apt update && \
			apt install -y apache2 libapache2-mod-php php php-mysql php-curl php-xml mysql-server \
			php-mbstring php7.0-ldap wget unzip dnsutils curl nano dialog \
			bash vim lsof procps net-tools netcat git tcpdump apt-utils php7.0-mcrypt phpmyadmin && \
		dpkg-reconfigure phpmyadmin && \
		phpenmod mcrypt

RUN		rm -rf /var/lib/apt/lists/* && \
    	a2enmod rewrite && \
			service apache2 restart && \
    	VAR_WWW_LINE=$(grep -n '<Directory /var/www/>' /etc/apache2/apache2.conf | cut -f1 -d:) && \
    	VAR_WWW_END_LINE=$(tail -n +${VAR_WWW_LINE} /etc/apache2/apache2.conf | grep -n '</Directory>' | head -n 1 | cut -f1 -d:) && \
    	REPLACE_ALLOW_OVERRIDE_LINE=$(($(tail -n +${VAR_WWW_LINE} /etc/apache2/apache2.conf | head -n "${VAR_WWW_END_LINE}" | grep -n AllowOverride | cut -f1 -d:) + ${VAR_WWW_LINE} - 1)) && \
    	sed -i "${REPLACE_ALLOW_OVERRIDE_LINE}s/None/All/" /etc/apache2/apache2.conf

RUN		service mysql start && \
    	while [ ! -S /var/run/mysqld/mysqld.sock ]; do sleep 1; done && \
    	sleep 5 ; \
			service mysql status ; \
			echo "use mysql; UPDATE user SET authentication_string=PASSWORD('${MYSQL_DATABASE_PASSWORD}') \
			WHERE user='root';UPDATE user SET plugin='mysql_native_password' WHERE user='root';FLUSH PRIVILEGES;" | mysql -u root && \
	cat /var/www/html/mutillidae/phpmyadmin/examples/create_tables.sql | mysql -u root && \
    	sed -i 's/^error_reporting.*/error_reporting = E_ALL/g' /etc/php/7.0/apache2/php.ini && \
    	sed -i 's/^display_errors.*/display_errors = On/g' /etc/php/7.0/apache2/php.ini

RUN		mkdir -p /var/www/html && \
			cd /var/www/html && \
			git clone https://github.com/webpwnized/mutillidae.git

RUN		sed -i 's/^Deny from all/Allow from all/g' /var/www/html/mutillidae/.htaccess && \
			sed -i "s/\['password'\] = ''/\['password'\] = \'${MYSQL_DATABASE_PASSWORD}\'/" /var/www/html/mutillidae/phpmyadmin/config.inc.php

# ##############################
# LDAP #########################
# ##############################
#
RUN		echo "127.0.0.1	mutillidae.local" >> /etc/hosts

RUN		OPENLDAP_USER_EXISTS=`id -u "${LDAP_OPENLDAP_USER}" 1>/dev/null 2>/dev/null; echo $?` ; \
			OPENLDAP_GROUP_EXISTS=`id -g "${LDAP_OPENLDAP_GROUP}" 1>/dev/null 2>/dev/null; echo $?`; \
			if [ "${OPENLDAP_GROUP_EXISTS}" -eq "1" ]; then \
			if [ -z "${LDAP_OPENLDAP_GID}" ]; then \
				groupadd -r "${LDAP_OPENLDAP_GROUP}" ; else \
				groupadd -r -g "${LDAP_OPENLDAP_GID}" "${LDAP_OPENLDAP_GROUP}"; fi; fi; \
			if [ "${OPENLDAP_USER_EXISTS}" -eq "1" ]; then \
				if [ -z "${LDAP_OPENLDAP_UID}" ]; then \
					useradd -r -g "${LDAP_OPENLDAP_GROUP}" "${LDAP_OPENLDAP_USER}"; else \
					useradd -r -g "${LDAP_OPENLDAP_GROUP}" -u "${LDAP_OPENLDAP_UID}" "${LDAP_OPENLDAP_USER}"; fi; fi;

RUN		apt-get -y update && \
			apt-get install -y --no-install-recommends ldap-utils expect

RUN		apt-get install -y slapd

RUN		id -u $LDAP_OPENLDAP_UID; \
			id -g $LDAP_OPENLDAP_GROUP; \
			chown -R "${LDAP_OPENLDAP_USER}":"${LDAP_OPENLDAP_GROUP}" /etc/ldap

# Automatization of dpkg-reconfigure
RUN		if [ -f /dpkg-reconfigure-expect.script ]; then rm -f /dpkg-reconfigure-expect.script; fi ;

RUN		echo '#!/usr/bin/expect' > /dpkg-reconfigure-expect.script && \
			echo >> /dpkg-reconfigure-expect.script && \
			echo "spawn dpkg-reconfigure slapd -freadline\nexpect \"Omit OpenLDAP server configuration?\"\nsend \"no\\\r\"\n" >> /dpkg-reconfigure-expect.script && \
			echo "expect \"DNS domain name: \"\nsend \"mutillidae.local\\\r\"\n\nexpect \"Organization name: \"\nsend \"mutillidae\\\r\"\n"  >> /dpkg-reconfigure-expect.script && \
			echo "expect \"Administrator password: \"\nsend \"mutillidae\\\r\"\n" >> /dpkg-reconfigure-expect.script && \
			echo "expect \"Confirm password: \"\nsend \"mutillidae\\\r\"\n" >> /dpkg-reconfigure-expect.script && \
			echo "expect \"Database backend to use: \"\nsend \"3\\\r\"\n" >> /dpkg-reconfigure-expect.script && \
			echo "expect \"Do you want the database to be removed when slapd is purged?\"\nsend \"yes\\\r\"\n" >> /dpkg-reconfigure-expect.script && \
			echo "expect \"Move old database?\"\nsend \"no\\\r\"\n" >> /dpkg-reconfigure-expect.script && \
			echo "expect eof" >> /dpkg-reconfigure-expect.script && cat /dpkg-reconfigure-expect.script

RUN		if [ -f /etc/ldap/slapd.conf ]; then rm -f /etc/ldap/slapd.conf ; fi && \
    	printf "#\n# LDAP Defaults\n#\n\n# See ldap.conf(5) for details\n# This file should be world readable but not world writable.\n\nBASE   dc=mutillidae,dc=local\nURI    ldaps://ldap.mutillidae.local\n\n#SIZELIMIT      12\n#TIMELIMIT      15\n#DEREF          never\n\n# TLS certificates (needed for GnuTLS)\nTLS_CACERT      /etc/ssl/certs/ca-certificates.crt" > /etc/ldap/slapd.conf

RUN 	service slapd start && \
			sleep 5 && \
			chmod +x /dpkg-reconfigure-expect.script && \
			unset DEBIAN_FRONTEND && \
			/dpkg-reconfigure-expect.script ; \
			TEST_LDAP=`ldapsearch -x -b 'dc=nodomain'`; \
			if [ -z `echo $TEST_LDAP | grep Success` ] ; then echo "[FAIL] LDAP test output result $TEST_LDAP"; \
			else echo ""; echo "[OK] LDAP test output: $TEST_LDAP"; fi ;

# ##############################
# phpLDAPadmin #################
# ##############################
# # sed -i "s@// $servers->setValue('server','host','127.0.0.1');@$servers->setValue('server','host','127.0.0.1');@" config/config.php && \
RUN		cd /var/www/html && \
			git clone https://github.com/leenooks/phpLDAPadmin.git && \
			cd phpLDAPadmin && \
			cp config/config.php.example config/config.php && \
			sed -i '162i$config->custom->appearance['hide_template_warning'] = true;' config/config.php && \
			sed -i 's/My LDAP Server/mutillidae LDAP Server/' config/config.php && \
			sed -i "301a\$servers->setValue('server','base',array('dc=mutillidae,dc=local'));" config/config.php && \
			sed -i "328a\$servers->setValue('login','bind_id','cn=admin,dc=mutillidae,dc=local');" config/config.php && \
			service apache2 restart ; \
			service slapd restart && \
			ldapadd -x -c -D 'cn=admin,dc=mutillidae,dc=local' -w "${LDAP_PASSWORD}" -f /var/www/html/mutillidae/data/mutillidae.ldif 2>/dev/null ; \
			echo

RUN		TEST_LDAP=`ldapsearch -x -b 'dc=mutillidae,dc=local' "objectClass=rooms"`; \
			if [ -z `echo $TEST_LDAP | grep Success` ] ; then echo "[FAIL] LDAP test output result $TEST_LDAP"; \
			else echo ""; echo "[OK] LDAP test output: $TEST_LDAP"; fi ;

# ##############################

# ##############################
# vim & .bashrc settings #######
# ##############################
echo "alias ll='ls -latr'" >> ~/.bashrc
echo "syntax on" > ~/.vimrc
echo "set number" >> ~/.vimrc
# ##############################

# ##############################
# start services 'by hands' ####
# ##############################
echo "You need to start services by yourself ;)"
echo "( service slapd start AND service mysql start AND service apache2 start )"


# ##############################
EXPOSE	80 3306 389 636 22

CMD		["bash", "-c", "sleep infinity & wait"]
