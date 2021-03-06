#!/usr/bin/env bash

echo -e "\nTHIS UPGRADER IS OBSOLETE AND MUST NOT BE USED"
echo "It is no longer compatible with Sentora core structure"
echo "To Install Sentora, please read infos at"
echo -e "    http://docs.sentora.org/?node=22\n"
exit

# OS VERSION: Ubuntu Server 12.04.x LTS
# ARCH: x32_64

SEN_VERSION=1.0.0
SEN_VERSION_ACTUAL=$(setso --show dbversion)

# Official Sentora Automated Upgrade Script
# =============================================
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# First we check if the user is 'root' before allowing the upgrade to commence
if [ $UID -ne 0 ]; then
    echo "Upgrade failed! To upgrade you must be logged in as 'root', please try again"
    exit 1;
fi

# Ensure the installer is launched and can only be launched on Ubuntu 12.04
BITS=$(uname -m | sed 's/x86_//;s/i[3-6]86/32/')
if [ -f /etc/lsb-release ]; then
  OS=$(cat /etc/lsb-release | grep DISTRIB_ID | sed 's/^.*=//')
  VER=$(cat /etc/lsb-release | grep DISTRIB_RELEASE | sed 's/^.*=//')
else
  OS=$(uname -s)
  VER=$(uname -r)
fi
echo "Detected : $OS  $VER  $BITS"
if [ "$OS" = "Ubuntu" ] && [ "$VER" = "12.04" ]; then
  echo "Ok."
else
  echo "Sorry, this upgrade script only supports the upgrade of Sentora on Ubuntu 12.04."
  exit 1;
fi

if [ "$SEN_VERSION" = "$SEN_VERSION_ACTUAL" ] ; then
echo "your version of Sentora already updated"
fi

# Set custom logging methods so we create a log file in the current working directory.
logfile=$$.log
exec > >(tee $logfile)
exec 2>&1

# Check that Sentora has been detected on the server if not, we'll exit!
if [ ! -d /etc/zpanel ]; then
    echo "Sentora has not been detected on this server, the upgrade script can therefore not continue!"
    exit 1;
fi

# Lets check that the user wants to continue first and recommend they have a backup!
echo ""
echo "The Sentora Upgrade script is now ready to start, we recommend that before"
echo "continuing that you first backup your Sentora server to enable a restore"
echo "in the event that something goes wrong during the upgrade process!"
echo ""
while true; do
read -e -p "Would you like to continue with the upgrade now (y/n)? " yn
    case $yn in
		[Yy]* ) break;;
		[Nn]* ) exit;
	esac
done

# Get mysql root password, check it works or ask it
mysqlpassword=$(cat /etc/zpanel/panel/cnf/db.php | grep "pass =" | sed -s "s|.*pass \= '\(.*\)';.*|\1|")
while ! mysql -u root -p$mysqlpassword -e ";" ; do
 read -p "Can't connect to mysql, please give root password or press ctrl-C to abort: " mysqlpassword
done
echo -e "Connection mysql ok"

# Now we'll ask upgrade specific automatic detection...

if [ "$SEN_VERSION_ACTUAL" = "10.1.1" ] ; then
upgradeto=1-0-0
SEN_VERSIONGIT=1.0.0
fi

# Now we'll ask upgrade specific questions...
echo -e ""
while true; do
	read -e -p "Sentora will now update from $SEN_VERSION_ACTUAL to $SEN_VERSIONGIT, are you sure (y/n)? " yn
	case $yn in
		 [Yy]* ) break;;
		 [Nn]* ) exit;
	esac
done


# We now clone the latest Sentora software from GitHub
echo "Downloading Sentora, Please wait, this may take several minutes, the installer will continue after this is complete!"
git clone https://github.com/sentora/sentora.git
cd zpanelx/
git checkout $SEN_VERSIONGIT
mkdir ../zp_install_cache/
git checkout-index -a -f --prefix=../zp_install_cache/
cd ../zp_install_cache/
rm -rf cnf/


# Lets run OS software updates
apt-get update -yqq
apt-get upgrade -yqq

# Now we make Sentora application/file specific updates
cp -R . /etc/zpanel/panel/
chmod -R 777 /etc/zpanel/
chmod 644 /etc/zpanel/panel/etc/apps/phpmyadmin/config.inc.php
cc -o /etc/zpanel/panel/bin/zsudo /etc/zpanel/configs/bin/zsudo.c
sudo chown root /etc/zpanel/panel/bin/zsudo
chmod +s /etc/zpanel/panel/bin/zsudo
sed -i "/symbolic-links=/a \secure-file-priv=/var/tmp" /etc/my.cnf

# Lets execute MySQL data upgrade scripts
cat /etc/zpanel/panel/etc/build/config_packs/ubuntu_12_04/sentora-update/$upgradeto/sql/*.sql | mysql -u root -p$mysqlpassword
updatemessage=""
for each in /etc/zpanel/panel/etc/build/config_packs/ubuntu_12_04/sentora-update/$upgradeto/shell/*.sh ; do
    updatemessage="$updatemessage\n"$(bash $each)  ;
done
# Disable PHP banner in apache server header
sed -i "s|expose_php = On|expose_php = Off|" /etc/php5/apache2/php.ini

# Remove phpMyAdmin's setup folder in case it was left behind
rm -rf /etc/zpanel/panel/etc/apps/phpmyadmin/setup

# We ensure that the daemons are registered for automatic startup and are restarted for changes to take effect
service apache2 start
service postfix restart
service dovecot start
service cron reload
service mysql start
service bind9 start
service proftpd start
service atd start
php /etc/zpanel/panel/bin/daemon.php

# We'll now remove the temporary install cache.
cd ../
rm -rf zpanelx/ zp_install_cache/

# We now display to the user(s) update SQL/BASH upgrade script messages etc.
echo -e ""
echo -e "###################################################################"
echo -e "# Please read and note down any update errors and messages below: #"
echo -e "# $updatemessage #"
echo -e "#                                                                 #"
echo -e "###################################################################"
echo -e ""

# We now recommend  that the user restarts their server...
while true; do
read -e -p "Restart your server now to complete the upgrade (y/n)? " rsn
	case $rsn in
		[Yy]* ) break;;
		[Nn]* ) exit;
	esac
done
shutdown -r now
