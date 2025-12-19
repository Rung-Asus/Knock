#!/bin/sh
#
#Knock.sh: Router Commands for non-admin users
#
#To Install:
#        1) Move script to /jffs/scripts/ directory
#        2) Run 'sh /jffs/scripts/knock.sh -install'
#        3) Update knock.cfg configuration file in the /jffs/addons/knock.d/ folder
#                Format of file is:
#                Port Number <space> Interface(s) [comma separated] <space> Command to execute [to end of line]
#                Default configuration file has use-case examples:
#                        Wake PC, reboot router, and run custom enable/disable scripts (e.g. for VPN Director rules)
#        3) Run '/jffs/scripts/knock.sh -start'
#
#Users can now execute commands by sending port knocks
#        (e.g. for main lan interface command, enter browser url: http://192.168.50.1:44444)
#
#To update configuration:
#        Run '/jffs/scripts/knock.sh -stop'
#        Update /jffs/addons/knock.d/knock.cfg
#        Run '/jffs/scripts/knock.sh -start'
#
#To Uninstall:
#        Run '/jffs/scripts/knock.sh -uninstall'
#
#
#Many thanks to @Viktor Jaep for all his help, input and testing of this script!
#Concepts in this script were derved from @Viktor Jaep's awesome Tailmon script
#Original concept credit to @RMerlin (https://www.snbforums.com/threads/wake-on-lan-per-http-https-script.7958/post-47811)
# Last Updated: 18DEC2025

REV="1.0b"
INTERVAL=5

fn=$(readlink -f "$0")
jf="/jffs"
id=$jf"/addons/knock.d"
cf=$id"/knock.cfg"
vf=$id"/version.txt"
js=$jf"/scripts"
sf=$js"/knock.sh"
pm=$js"/post-mount"
fs=$js"/firewall-start"
giturl="https://raw.githubusercontent.com/Rung-Asus/Knock/main"

if [ "$1" = "-version" ]; then
	echo "Version" $REV
	exit
fi

if [ "$1" = "-screen" ]; then
	if [ ! -f "/opt/sbin/screen" ]; then
		logger -t "knock.sh" "Error: Entware Screen app not installed"
		exit
	fi
	if [ ! -f $sf ]; then
		logger -t "knock.sh" "Error: knock.sh not installed yet"
		exit
	fi

	logger -t "knock.sh" "Starting knock.sh background process"

	/opt/sbin/screen -S knock -X quit > /dev/null
	/opt/sbin/screen -dmS knock "$sf" -loop
	exit
fi

if [ "$1" = "-firewall" ]; then
	if [ ! -f $cf ]; then
		logger -t "knock.sh" "Error: Missing configuration file" $cf
		exit
	fi

	logger -t "knock.sh" "Adding knock ports to iptables"

	while read port interfaces cmd
	do
		if [ -n "$port" ] && [ $(echo $port | cut -c 1-1) != "#" ]; then
			for interface in $(echo $interfaces | tr ',' ' '); do
				iptables -D INPUT -i $interface -p tcp -m tcp --dport $port -j LOG --log-prefix "knock.sh " --log-level info 2> /dev/null
				iptables -I INPUT -i $interface -p tcp -m tcp --dport $port -j LOG --log-prefix "knock.sh " --log-level info
			done
		fi
	done < $cf

	exit
fi

if [ "$1" = "-install" ]; then
	if [ "$fn" != "$sf" ]; then
		echo "Error: This script must be run from" $js
		exit
	fi
	chmod 755 $sf

	if [ ! -f "/opt/sbin/screen" ]; then
		echo "Please install Entware Screep app first"
		echo "Run this command: 'opkg install screen'"
		exit
	fi

	if [ ! -d $jf"/addons" ]; then
		echo "Error: This script is designed for Asuswrt-Merlin firmware only"
		exit
	fi
	mkdir $id 2>/dev/null

	if [ ! -f $cf ]; then
		cat <<EOF > $cf
#knock.sh example configuration file

#Format Port Number <space> Interface(s) [comma separated] <space> Command to execute [to end of line]

#Wake up PC if 44444 knock comes from main lan, tailscale (lo), or wireguard server (wgs1)
44444 br0,lo,wgs1 ether-wake -i br0 xx:xx:xx:xx:xx:xx

#Reboot router if 44445 knock comes from main lan, tailscale (lo), or wireguard server (wgs1)
44445 br0,lo,wgs1 reboot

#enable script example
44446 br0 /jffs/scripts/enable-example.sh

#disable script example
44447 br0 /jffs/scripts/disable-example.sh

EOF
	fi

	if ! [ -f $pm ]; then
		echo "#!/bin/sh" > $pm
      		echo "" >> $pm
		chmod 755 $pm
	fi
	sed -i -e '/knock.sh/d' $pm
	echo "(sleep 30 &&" $sf "-screen) & # Added by knock.sh" >> $pm

	if ! [ -f $fs ]; then
		echo "#!/bin/sh" > $fs
      		echo "" >> $fs
		chmod 755 $fs
	fi
	sed -i -e '/knock.sh/d' $fs
	echo $sf "-firewall # Added by knock.sh" >> $fs

	clear
	echo "Knock.sh installed"
	echo ""
	echo "Please update the configuration file" $cf
	echo ""
	echo "Default configuration file has use-case examples:"
	echo -e "\tWake PC, reboot router, run custom enable/disable scripts (e.g. for VPN Director rules)"
	echo ""
	echo "Once updated, start knock.sh run with this command:" $sf "-start"
	exit
fi

if [ "$1" = "-start" ] || [ "$1" = "-restart" ]; then
	if [ ! -f $cf ]; then
		echo "Error: Missing configuration file" $cf
		exit
	fi

	service restart_firewall >/dev/null

	$sf "-screen"

	clear
	echo "Knock.sh started and ready for port knocks"
	echo ""
	echo "The following ports/interfaces will execute these router commands:"

	while read port interfaces cmd
	do
		if [ -n "$port" ] && [ $(echo $port | cut -c 1-1) != "#" ]; then
			echo "	Port" $port "on" $interfaces "Command:" "$cmd"
		fi
	done < $cf

	exit
fi

if [ "$1" = "-stop" ]; then
	screen -S knock -X quit > /dev/null
	echo "knock.sh stopped"
	exit
fi

if [ "$1" = "-uninstall" ]; then
	screen -S knock -X quit > /dev/null
	sed -i -e '/knock.sh/d' $pm
	sed -i -e '/knock.sh/d' $fs
	service restart_firewall >/dev/null

	rm $sf
	cp $cf /tmp/knock.cfg
	rm $cf
	rm $vf 2> /dev/null

	if [ $(pwd) = $id ]; then
		echo "Error: cannot remove install directory" $id
	else
		rmdir $id 2>/dev/null
	fi

	echo "Knock.sh uninstalled"
	echo "Existing configuration file saved as /tmp/knock.cfg"
	exit
fi

if [ "$1" = "-update" ]; then
	#Tailmon.sh function
	function promptyn {
		while true; do
			read -p "$1" -n 1 -r yn
			case "${yn}" in
				[Yy]* ) return 0 ;;
				[Nn]* ) return 1 ;;
				* ) echo -e "\nPlease answer y or n.";;
			esac
		done }

	rm $vf 2> /dev/null
	#curl --silent --retry 3 --connect-timeout 3 --max-time 6 --retry-delay 1 --retry-all-errors --fail "https://raw.githubusercontent.com/Rung-Asus/Knock/refs/heads/main/version.txt" -o $vf
	curl --silent --retry 3 --connect-timeout 3 --max-time 6 --retry-delay 1 --retry-all-errors --fail $giturl"/version.txt" -o $vf
	if [ -f $vf ]; then
		nv=$(cat $vf | head -n 1)
		echo "Latest version:" $nv
		echo "Current version:" $REV
		if  promptyn "Proceed with update? (y/n):" ; then
			echo -e "\nDownloading..."
			#curl --silent --retry 3 --connect-timeout 3 --max-time 6 --retry-delay 1 --retry-all-errors --fail "https://raw.githubusercontent.com/Rung-Asus/Knock/refs/heads/main/knock.sh" -o $sf
			curl --silent --retry 3 --connect-timeout 3 --max-time 6 --retry-delay 1 --retry-all-errors --fail $giturl"/knock.sh" -o $sf
			chmod 755 $sf
			echo "Installing..."
			$sf -install >/dev/null
			echo "Restarting..."
			$sf -start >/dev/null
			echo "Update completed."
			echo "Installed version is now:"
			$sf -version
		else
			echo -e "\nNo update performed"
		fi
	else
		echo "Error: network issue"
	fi
	exit
fi


if [ "$1" != "-loop" ]; then
	echo "Knock.sh: Router Commands for non-admin users"
	echo "Revision" $REV
	echo ""
	echo "To Install:"
	echo -e "\t1) Move script to" $js"/ directory"
	echo "	2) Run 'sh" $sf "-install'"
	echo "	3) Update knock.cfg configuration file in the" $id"/ folder"
        echo "		Format of file is:"
        echo "		Port Number <space> Interface(s) [comma separated] <space> Command to execute [to end of line]"
	echo -e "\t\tDefault configuration file has use-case examples:"
	echo -e "\t\t\tWake PC, reboot router, and run custom enable/disable scripts (e.g. for VPN Director rules)"
	echo "	3) Run '"$sf "-start'"
	echo ""
	echo "Users can now execute commands by sending port knocks"
	echo "	(e.g. for main lan interface command, enter browser url: http://192.168.50.1:44444)"
	echo ""
	echo "To update configuration:"
	echo "	Run '"$sf "-stop'"
	echo "	Update" $cf
	echo "	Run '"$sf "-start'"
	echo ""
	echo "To Uninstall:"
	echo "	Run '"$sf "-uninstall'"
	echo ""
	exit
fi

if [ ! -f $cf ]; then
	echo "Error: Missing configuration file" $cf
	logger -t "knock.sh" "Error: Missing configuration file" $cf
	exit
fi

function readDATA {
	dmesg | grep "knock.sh" | tail -n 1 | awk '{print $11 " " $15 " " $2}'; }
function readID {
	echo $DATA | awk '{print $1}' | awk -F '=' '{print $2}'; }

DATA=$(readDATA)
oldID=$(readID)


echo "Knock.sh started"
echo "Version" $REV
echo "Waiting for port knocks..."
logger -t "knock.sh" "Waiting for port knocks..."
while sleep $INTERVAL;do
	DATA=$(readDATA)
	ID=$(readID)
	if [ "$ID" != "$oldID" ]; then
		KPORT=$(echo $DATA | awk '{print $2}' | awk -F '=' '{print $2}')
		KINT=$(echo $DATA | awk '{print $3}' | awk -F '=' '{print $2}')
		echo  "Knock detected on interface" $KINT "into port" $KPORT "with ID" $ID
		logger -t "knock.sh" "Knock detected on interface" $KINT "into port" $KPORT "with ID" $ID

		while read port interfaces cmd
		do
			if [ -n "$port" ] && [ $(echo $port | cut -c 1-1) != "#" ]; then
				if [ "$KPORT" = "$port" ]; then
					echo "Executing command:" "$cmd"
					logger -t "knock.sh" "Executing command:" "$cmd"
					$cmd &
				fi
			fi
		done < $cf

		sleep $INTERVAL
		sleep $INTERVAL
		DATA=$(readDATA)
		oldID=$(readID)
	fi
done
