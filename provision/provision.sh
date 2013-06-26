# provision.sh
#
# This file is specified in Vagrantfile and is loaded by Vagrant as the primary
# provisioning script whenever the commands `vagrant up`, `vagrant provision`,
# or `vagrant reload` are used. It provides all of the default packages and
# configurations included with Varying Vagrant Vagrants.

# We calculate the duration of provisioning at the end of this script.
start_seconds=`date +%s`

# SYMLINK HOST FILES
printf "\nLink Directories...\n"

# Configuration for nginx
ln -sf /srv/config/nginx-config/nginx.conf /etc/nginx/nginx.conf | echo "Linked nginx.conf to /etc/nginx/"
ln -sf /srv/config/nginx-config/nginx-wp-common.conf /etc/nginx/nginx-wp-common.conf | echo "Linked nginx-wp-common.conf to /etc/nginx/"

# Configuration for php5-fpm
ln -sf /srv/config/php5-fpm-config/www.conf /etc/php5/fpm/pool.d/www.conf | echo "Linked www.conf to /etc/php5/fpm/pool.d/"

# Provide additional directives for PHP in a custom ini file
ln -sf /srv/config/php5-fpm-config/php-custom.ini /etc/php5/fpm/conf.d/php-custom.ini | echo "Linked php-custom.ini to /etc/php5/fpm/conf.d/php-custom.ini"

# Configuration for Xdebug - Mod disabled by default
ln -sf /srv/config/php5-fpm-config/xdebug.ini /etc/php5/fpm/conf.d/xdebug.ini | echo "Linked xdebug.ini to /etc/php5/fpm/conf.d/xdebug.ini"

# Configuration for APC
ln -sf /srv/config/php5-fpm-config/apc.ini /etc/php5/fpm/conf.d/apc.ini | echo "Linked apc.ini to /etc/php5/fpm/conf.d/"

# Configuration for mysql
cp /srv/config/mysql-config/my.cnf /etc/mysql/my.cnf | echo "Linked my.cnf to /etc/mysql/"

# Configuration for memcached
ln -sf /srv/config/memcached-config/memcached.conf /etc/memcached.conf | echo "Linked memcached.conf to /etc/"

# Custom bash_profile for our vagrant user
ln -sf /srv/config/bash_profile /home/vagrant/.bash_profile | echo "Linked .bash_profile to vagrant user's home directory..."

# Custom bash_aliases included by vagrant user's .bashrc
ln -sf /srv/config/bash_aliases /home/vagrant/.bash_aliases | echo "Linked .bash_aliases to vagrant user's home directory..."

# Custom vim configuration via .vimrc
ln -sf /srv/config/vimrc /home/vagrant/.vimrc | echo "Linked vim configuration to home directory..."


# RESTART SERVICES
#
# Make sure the services we expect to be running are running.
printf "\nRestart services...\n"
printf "service nginx restart\n"
service nginx restart
printf "service php5-fpm restart\n"
service php5-fpm restart
printf "service memcached restart\n"
service memcached restart

# MySQL gives us an error if we restart a non running service, which
# happens after a `vagrant halt`. Check to see if it's running before
# deciding whether to start or restart.
exists_mysql=`service mysql status`
if [ "mysql stop/waiting" == "$exists_mysql" ]
then
	printf "service mysql start"
	service mysql start
else
	printf "service mysql restart"
	service mysql restart
fi

# IMPORT SQL
#
# Create the databases (unique to system) that will be imported with
# the mysqldump files located in database/backups/
if [ -f /srv/database/init-custom.sql ]
then
	mysql -u root -pblank < /srv/database/init-custom.sql | printf "\nInitial custom MySQL scripting...\n"
else
	printf "\nNo custom MySQL scripting found in database/init-custom.sql, skipping...\n"
fi

# Setup MySQL by importing an init file that creates necessary
# users and databases that our vagrant setup relies on.
mysql -u root -pblank < /srv/database/init.sql | echo "Initial MySQL prep...."

# Process each mysqldump SQL file in database/backups to import 
# an initial data set for MySQL.
sudo mysqladmin -s -uroot -pblank drop spare_hanger --force
sudo mysqladmin -s -uroot -pblank create spare_hanger --force
sudo mysql -s -uroot -pblank -e 'GRANT ALL PRIVILEGES ON spare_hanger.* \
  TO "spare_hanger"@"localhost" IDENTIFIED BY "SecurePassword42";'
  sudo mysql -s -uroot -pblank -e 'GRANT ALL PRIVILEGES ON spare_hanger.* \
  TO "spare_hanger"@"any" IDENTIFIED BY "SecurePassword42";'
sudo mysql -s -uspare_hanger -pSecurePassword42 -h localhost \
  spare_hanger < /srv/www/sparehanger/sparehanger/protected/data/spare_hanger.sql


# Download phpMyAdmin 4.0.3
if [ ! -d /srv/www/default/database-admin ]
then
	printf "Downloading phpMyAdmin 4.0.3....\n"
	cd /srv/www/default
	wget -q -O phpmyadmin.tar.gz 'http://sourceforge.net/projects/phpmyadmin/files/phpMyAdmin/4.0.3/phpMyAdmin-4.0.3-english.tar.gz/download#!md5!07dc6ed4d65488661d2581de8d325493'
	tar -xf phpmyadmin.tar.gz
	mv phpMyAdmin-4.0.3-english database-admin
	rm phpmyadmin.tar.gz
else
	printf "PHPMyAdmin 4.0.3 already installed.\n"
fi

# Add any custom domains to the virtual machine's hosts file so that it
# is self aware. Enter domains space delimited as shown with the default.
DOMAINS='local.sparehanger.dev'
if ! grep -q "$DOMAINS" /etc/hosts
then echo "127.0.0.1 $DOMAINS" >> /etc/hosts
fi

end_seconds=`date +%s`
echo -----------------------------
echo Provisioning complete in `expr $end_seconds - $start_seconds` seconds
echo For further setup instructions, visit http://192.168.50.4
echo "Welcome to Sparehanger's Vangrant box"
