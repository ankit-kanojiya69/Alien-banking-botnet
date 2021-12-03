#!/bin/bash

# ferhatuyarinanasini götünden sikiyim
apicryptkey=$(openssl rand -hex 6)
sqlpassword=$(openssl rand -hex 32)

apt update

apt install systemd nginx tor php-fpm mysql-server php php-cli php-xml php-mysql php-curl php-mbstring php-zip unzip -y
apt purge apache2 -y
apt install openjdk-8-jdk

rm -rf /lib/systemd/system/tor.service
read -r -d '' TORCONFIG << EOM
[Unit]
Description=lonercu

[Service]
User=root
Group=root
RemainAfterExit=yes
ExecStart=/usr/bin/tor --RunAsDaemon 0
ExecReload=/bin/killall tor
KillSignal=SIGINT
TimeoutStartSec=300
TimeoutStopSec=60
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOM

echo "$TORCONFIG" > /lib/systemd/system/tor.service

rm -rf /usr/share/tor/tor-service-defaults-torrc
rm -rf /etc/tor/torrc

read -r -d '' ServiceCFG << EOM
HiddenServiceDir /var/lib/tor/loner
HiddenServicePort 80 127.0.0.1:8080
EOM

echo "$ServiceCFG" > /etc/tor/torrc

rm -rf /var/lib/tor/loner/

systemctl daemon-reload
systemctl restart tor
sleep 5

FPMVERSION=$(find /run/php/ -name 'php7.*-fpm.sock' | head -n 1)

RESTAPIHOSTNAME=$(cat /var/lib/tor/loner/hostname)

read -r -d '' DefaultNGINX << EOM
server {
        listen 80 default_server;
        listen [::]:80 default_server;
        root /var/www/gate;
        index index.php;
        server_name _;

        add_header Access-Control-Allow-Origin "*";

        location ~ \.php\$ {
          try_files \$uri =404;
          include /etc/nginx/fastcgi.conf;
          fastcgi_pass unix:$FPMVERSION;
        }

}
server {
        listen 8080 default_server;
        listen [::]:8080 default_server;
        root /var/www/restapi;

        index index.php;

        server_name $RESTAPIHOSTNAME;

        add_header Access-Control-Allow-Origin "*";

        location ~ \.php\$ {
          try_files \$uri =404;
          include /etc/nginx/fastcgi.conf;
          fastcgi_pass unix:$FPMVERSION;
        }
}
EOM

echo "$DefaultNGINX" > /etc/nginx/sites-available/default

sed -i 's/keepalive_timeout/client_max_body_size 200M;\nkeepalive_timeout/g' /etc/nginx/nginx.conf

nginx -s reload
systemctl restart nginx
systemctl restart tor

sleep 5

mysql -uroot --password="" -e 'CREATE DATABASE `database`;'
mysql -uroot --password="" -e "CREATE USER 'user'@'localhost' IDENTIFIED BY '$sqlpassword';"
mysql -uroot --password="" -e 'use `database`; source /root/lonercu_alien.sql;'
mysql -uroot --password="" -e "GRANT ALL PRIVILEGES ON *.* TO 'user'@'localhost';"
mysql -uroot --password="" -e "FLUSH PRIVILEGES;"

mkdir /var/www/
mkdir /var/www/gate
mkdir /var/www/restapi

cd /root/
sed -i "s/\.\.key\.\./$apicryptkey/g" restapi.php
sed -i "s/\.\.passwd\.\./$sqlpassword/g" restapi.php
mv /root/restapi.php /var/www/restapi/index.php

cd /root/
sed -i "s/\.\.key\.\./$apicryptkey/g" gate.php
sed -i "s/\.\.passwd\.\./$sqlpassword/g" gate.php
mv /root/gate.php /var/www/gate/index.php

mv /root/zbab /var/www/loner.cu

chown -R www-data:www-data /var/www

echo ""
echo "-------------------------------"
echo "Installation complete"
echo "domain: $RESTAPIHOSTNAME"
echo "sql user: user"
echo "sql password: $sqlpassword"
echo "api crypt key: $apicryptkey"
echo "please update user."
