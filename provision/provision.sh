# provision.sh
#
# This file is specified in Vagrantfile and is loaded by Vagrant as the primary
# provisioning script whenever the commands `vagrant up`, `vagrant provision`,
# or `vagrant reload` are used. It provides all of the default packages and
# configurations included with Varying Vagrant Vagrants.

# We calculate the duration of provisioning at the end of this script.
start_seconds=`date +%s`

# PACKAGE INSTALLATION
#
# Build a bash array to pass all of the packages we want to install to a single
# apt-get command. This avoids having to do all the leg work each time a
# package is set to install. It also allows us to easily comment out or add
# single packages. We set the array as empty to begin with so that we can
# append individual packages to it as required.
apt_package_install_list=()

# Start with a bash array containing all of the packages that we want to 
# install on the system. We'll then loop through each of these and check
# individual status before passing to the apt_package_install_list array.
apt_package_check_list=(

	# PHP5
	#
	# Our base packages for php5. As long as php5-fpm and php5-cli are
	# installed, there is no need to install the general php5 package, which
	# can sometimes install apache as a requirement.
	php5-fpm
	php5-cli

	# Common and dev packages for php
	php5-common
	php5-dev

	# Extra PHP modules that we find useful
	php5-memcache
	php5-imagick
	php5-xdebug
	php5-mcrypt
	php5-mysql
	php5-imap
	php5-curl
	php-pear
	php5-gd
	php-apc

	# nginx is installed as the default web server
	nginx

	# memcached is made available for object caching
	memcached

	# other packages that come in handy
	imagemagick
	subversion
	git-core
	unzip
	ngrep
	curl
	make
	vim

	# dos2unix
	# Allows conversion of DOS style line endings to something we'll have less
	# trouble with in Linux.
	dos2unix
)

echo "Check for packages to install..."

# Loop through each of our packages that should be installed on the system. If
# not yet installed, it should be added to the array of packages to install.
for pkg in "${apt_package_check_list[@]}"
do
	if dpkg -s $pkg | grep -q 'Status: install ok installed';
	then 
		echo $pkg already installed
	else
		echo $pkg not yet installed
		apt_package_install_list+=($pkg)
	fi
done

# MySQL
#
# The current state of MySQL should be done outside of the looping done above.
# This allows us to set the MySQL specific settings for the root password
# so that provisioning does not require any user input.
if dpkg -s mysql-server | grep -q 'Status: install ok installed';
then
	echo "mysql-server already installed"
else 
	# We need to set the selections to automatically fill the password prompt
	# for mysql while it is being installed. The password in the following two
	# lines *is* actually set to the word 'blank' for the root user.
	echo mysql-server mysql-server/root_password password blank | debconf-set-selections
	echo mysql-server mysql-server/root_password_again password blank | debconf-set-selections
	apt_package_install_list+=('mysql-server')
fi

# Provide our custom apt sources before running `apt-get update`
ln -sf /srv/config/apt-source-append.list /etc/apt/sources.list.d/vvv-sources.list | echo "Linked custom apt sources"

# If there are any packages to be installed in the apt_package_list array,
# then we'll run `apt-get update` and then `apt-get install` to proceed.
if [ ${#apt_package_install_list[@]} = 0 ];
then 
	printf "No packages to install.\n\n"
else
	# Before running `apt-get update`, we should add the public keys for
	# the packages that we are installing from non standard sources via
	# our appended apt source.list

	# Nginx.org nginx key ABF5BD827BD9BF62
	gpg -q --keyserver keyserver.ubuntu.com --recv-key ABF5BD827BD9BF62
	gpg -q -a --export ABF5BD827BD9BF62 | apt-key add -

	# Launchpad Subversion key EAA903E3A2F4C039
	gpg -q --keyserver keyserver.ubuntu.com --recv-key EAA903E3A2F4C039
	gpg -q -a --export EAA903E3A2F4C039 | apt-key add -

	# Launchpad PHP key 4F4EA0AAE5267A6C
	gpg -q --keyserver keyserver.ubuntu.com --recv-key 4F4EA0AAE5267A6C
	gpg -q -a --export 4F4EA0AAE5267A6C | apt-key add -

	# Launchpad git key A1715D88E1DF1F24
	gpg -q --keyserver keyserver.ubuntu.com --recv-key A1715D88E1DF1F24
	gpg -q -a --export A1715D88E1DF1F24 | apt-key add -

	# update all of the package references before installing anything
	printf "Running apt-get update....\n"
	apt-get update --assume-yes

	# install required packages
	printf "Installing apt-get packages...\n"
	apt-get install --assume-yes ${apt_package_install_list[@]}

	# Clean up apt caches
	apt-get clean			
fi

# ack-grep
#
# Install ack-rep directory from the version hosted at beyondgrep.com as the
# PPAs for Ubuntu Precise are not available yet.
if [ -f /usr/bin/ack ]
then
	echo "ack-grep already installed"
else
	echo "Installing ack-grep as ack"
	curl -s http://beyondgrep.com/ack-2.04-single-file > /usr/bin/ack && chmod +x /usr/bin/ack
fi

# COMPOSER
#
# Install or Update Composer based on current state. Updates are direct from
# master branch on GitHub repository.
if composer --version | grep -q 'Composer version';
then
	printf "Updating Composer...\n"
	composer self-update
else
	printf "Installing Composer...\n"
	curl -sS https://getcomposer.org/installer | php
	chmod +x composer.phar
	mv composer.phar /usr/local/bin/composer
fi

# PHPUnit
#
# Check that PHPUnit, Mockery, and Hamcrest are all successfully installed. If
# not, then Composer should be given another shot at it. Versions for these
# packages are controlled in the `/srv/config/phpunit-composer.json` file.
if [ ! -d /usr/local/src/vvv-phpunit ]
then
	printf "Installing PHPUnit, Hamcrest and Mockery...\n"
	mkdir -p /usr/local/src/vvv-phpunit
	cp /srv/config/phpunit-composer.json /usr/local/src/vvv-phpunit/composer.json
	sh -c "cd /usr/local/src/vvv-phpunit && composer install"
else
	cd /usr/local/src/vvv-phpunit
	if composer show -i | grep -q 'mockery'; then echo 'Mockery installed';else vvvphpunit_update=1;fi
	if composer show -i | grep -q 'phpunit'; then echo 'PHPUnit installed'; else vvvphpunit_update=1;fi
	if composer show -i | grep -q 'hamcrest'; then echo 'Hamcrest installed'; else vvvphpunit_update=1;fi
	cd ~/
fi

if [ "$vvvphpunit_update" = 1 ]
then
	printf "Update PHPUnit, Hamcrest and Mockery...\n"
	cp /srv/config/phpunit-composer.json /usr/local/src/vvv-phpunit/composer.json
	sh -c "cd /usr/local/src/vvv-phpunit && composer update"
fi

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
php5dismod xdebug
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
  spare_hanger < /vagrant/www/sparehanger/sparehanger/protected/data/spare_hanger.sql

sudo chown vagrant:vagrant /var/lib/phpmyadmin/tmp
sudo cp /vagrant/config/php.ini /etc/php5/apache2/php.ini


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
