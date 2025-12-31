#!/bin/sh
#
#Knock.sh: Router Commands for non-admin users
#
#To install:
#        1) Move script to /jffs/scripts/ directory
#        2) Run 'sh /jffs/scripts/knock.sh -install'
#        3) Update knock.cfg configuration file in the /jffs/addons/knock.d/ folder
#                Format of file is:
#                Port Number <space> Interface(s) [comma separated] <space> Command to execute [to end of line]
#                Default configuration file has use-case examples:
#                        Wake PC, reboot router, and run custom enable/disable scripts (e.g. for VPN Director rules)
#        4) Run '/jffs/scripts/knock.sh -start'
#
#Users can now execute commands by sending port knocks
#        (e.g. for main lan interface command, enter browser url: http://192.168.50.1:44444)
#
#To update configuration:
#        Run '/jffs/scripts/knock.sh -stop'
#        Update /jffs/addons/knock.d/knock.cfg
#        Run '/jffs/scripts/knock.sh -start'
#
#To display current configuration file information:
#        Run '/jffs/scripts/knock.sh -config'
#
#To update to the lastest version of script:
#        Run '/jffs/scripts/knock.sh -update'
#
#To uninstall:
#        Run '/jffs/scripts/knock.sh -uninstall'
#
#Many thanks to @Viktor Jaep for all his help, input and testing of this script!
#Concepts in this script were derved from @Viktor Jaep's awesome Tailmon script
#Original concept credit to @RMerlin (https://www.snbforums.com/threads/wake-on-lan-per-http-https-script.7958/post-47811)
# Last Updated: 31DEC2025

REV="1.2"
INTERVAL=5
DOUBLE_KNOCK_WAIT=30

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

function showconfig {
	echo -e "The following ports/interfaces will execute these router commands:\n"
	lastcomment=""
	commandnum=0
	while read ports interfaces cmd
	do
		if [ -n "$ports" ]; then
			if [ $(echo $ports | cut -c 1-1) != "#" ]; then
				commandnum=$(($commandnum+1))
				echo "Command #" $commandnum
				echo -e "\t"$lastcomment
				echo -e "\tPort(s)" $ports "on" $interfaces
				echo -e "\tCommand:" "$cmd"
				interface=$(echo $interfaces | awk -F',' '{print $1}')
				port1=$(echo $ports | awk -F',' '{print $1}')
				echo -e "\tURL to initiate command:" $(ifconfig  $interface | awk '{print $2}' | grep addr | sed 's/addr:/http:\/\//g')":"$port1
				port2=$(echo $ports | awk -F',' '{print $2}')
				if [ -n "$port2" ]; then
					echo -e "\t\tWait" $(( $INTERVAL * 3 )) "seconds then URL to complete command:" $(ifconfig  $interface | awk '{print $2}' | grep addr | sed 's/addr:/http:\/\//g')":"$port2
				fi
				echo -e ""
			else
				lastcomment=$(echo "$ports $interfaces $cmd" | cut -c 2-)
			fi
		fi
	done < $cf
}

if [ "$1" = "-version" ]; then
	echo "Version" $REV
	exit
fi

if [ "$1" = "-screen" ]; then
	if [ ! -f "/opt/sbin/screen" ]; then
		logger -t "knock.sh" "Error: Entware Screen app not installed"
		exit 1
	fi
	if [ ! -f $sf ]; then
		logger -t "knock.sh" "Error: knock.sh not installed yet"
		exit 1
	fi

	logger -t "knock.sh" "Starting knock.sh background process"

	/opt/sbin/screen -S knock -X quit > /dev/null
	/opt/sbin/screen -dmS knock "$sf" -loop
	exit
fi

if [ "$1" = "-firewall" ]; then
	if [ ! -f $cf ]; then
		logger -t "knock.sh" "Error: Missing configuration file" $cf
		exit 1
	fi

	logger -t "knock.sh" "Adding knock ports to iptables"

	while read ports interfaces cmd
	do
		if [ -n "$ports" ] && [ $(echo $ports | cut -c 1-1) != "#" ]; then
			COUNT=0
			for port in $(echo $ports | tr ',' ' '); do
				COUNT=$(($COUNT+1))
				if [ $COUNT -gt 2 ]; then
					break
				fi
				for interface in $(echo $interfaces | tr ',' ' '); do
					iptables -D INPUT -i $interface -p tcp -m tcp --dport $port -j LOG --log-prefix "knock.sh " --log-level info 2> /dev/null
					iptables -I INPUT -i $interface -p tcp -m tcp --dport $port -j LOG --log-prefix "knock.sh " --log-level info
				done
			done
		fi
	done < $cf

	exit
fi

if [ "$1" = "-install" ]; then
	if [ "$fn" != "$sf" ]; then
		echo "Error: This script must be run from" $js
		exit 1
	fi
	chmod 755 $sf

	if [ ! -f "/opt/sbin/screen" ]; then
		echo "Please install Entware Screep app first"
		echo "Run this command: 'opkg install screen'"
		exit 1
	fi

	if [ ! -d $jf"/addons" ]; then
		echo "Error: This script is designed for Asuswrt-Merlin firmware only"
		exit 1
	fi
	mkdir $id 2>/dev/null

	if [ ! -f $cf ]; then
		cat <<EOF > $cf
#knock.sh Example configuration file

#Format Port Number <space> Interface(s) [comma separated] <space> Command to execute [to end of line]

#Wake up PC if 44444 knock comes from main lan, tailscale (lo), or wireguard server (wgs1)
44444 br0,lo,wgs1 ether-wake -i br0 xx:xx:xx:xx:xx:xx

#Reboot router if 44445 knock comes from main lan, tailscale (lo), or wireguard server (wgs1)
44445 br0,lo,wgs1 reboot

#Turn on VPN client
44446 br0 /jffs/scripts/enable-wireguard-rule.sh

#Turn off vpn client
44447 br0 /jffs/scripts/disable-wireguard-rule.sh

#Sensitive command. Only execute command after a knock from two different ports (15 seconds apart)
44449,44410 br0 /jffs/scripts/doubleknock.sh

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
	echo "Knock.sh Rev" $REV "installed"
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
		exit 1
	fi

	service restart_firewall >/dev/null

	if $sf "-screen"; then
		clear
		echo "Knock.sh Rev" $REV "started and ready for port knocks"
		echo ""
		showconfig
		exit
	else
		echo "Error: Cannot start knock in background"
		exit 1
	fi
fi

if [ "$1" = "-config" ]; then
	if [ ! -f $cf ]; then
		echo "Error: Missing configuration file" $cf
		exit 1
	fi
	clear
	showconfig
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
	curl --silent --retry 3 --connect-timeout 3 --max-time 6 --retry-delay 1 --retry-all-errors --fail $giturl"/version.txt" -o $vf
	if [ -f $vf ]; then
		nv=$(cat $vf | head -n 1)
		echo "Latest version:" $nv
		echo "Current version:" $REV
		if  promptyn "Proceed with update? (y/n):" ; then
			echo -e "\nDownloading..."
			curl --silent --retry 3 --connect-timeout 3 --max-time 6 --retry-delay 1 --retry-all-errors --fail $giturl"/knock.sh" -o $sf
			chmod 755 $sf
			echo "Installing..."
			$sf -install >/dev/null
			echo "Restarting..."
			$sf -start >/dev/null
			echo "Update completed."
			echo "Installed version is now:"
			$sf -version
			echo ""
			showconfig
		else
			echo -e "\nNo update performed"
		fi
	else
		echo "Error: network issue"
		exit 1
	fi
	exit
fi

if [ "$1" != "-loop" ]; then
	echo "Knock.sh: Router Commands for non-admin users"
	echo "Version" $REV
	echo ""
	echo "To install:"
	echo -e "\t1) Move script to" $js"/ directory"
	echo "	2) Run 'sh" $sf "-install'"
	echo "	3) Update knock.cfg configuration file in the" $id"/ folder"
        echo "		Format of file is:"
        echo "		Port Number <space> Interface(s) [comma separated] <space> Command to execute [to end of line]"
	echo -e "\t\tDefault configuration file has use-case examples:"
	echo -e "\t\t\tWake PC, reboot router, and run custom enable/disable scripts (e.g. for VPN Director rules)"
	echo "	4) Run '"$sf "-start'"
	echo ""
	echo "Users can now execute commands by sending port knocks"
	echo "	(e.g. for main lan interface command, enter browser url: http://192.168.50.1:44444)"
	echo ""
	echo "To update configuration:"
	echo "	Run '"$sf "-stop'"
	echo "	Update" $cf
	echo "	Run '"$sf "-start'"
	echo ""
	echo "To display current configuration file information:"
	echo "	Run '"$sf "-config'"
	echo ""
	echo "To update to the lastest version of script:"
	echo "	Run '"$sf "-update'"
	echo ""
	echo "To uninstall:"
	echo "	Run '"$sf "-uninstall'"
	echo ""
	exit
fi

if [ ! -f $cf ]; then
	echo "Error: Missing configuration file" $cf
	logger -t "knock.sh" "Error: Missing configuration file" $cf
	exit 1
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

		while read ports interfaces cmd
		do
			if [ -n "$ports" ] && [ $(echo $ports | cut -c 1-1) != "#" ]; then
				port1=$(echo $ports | awk -F',' '{print $1}')
				port2=$(echo $ports | awk -F',' '{print $2}')
				if [ -n "$port2" ]; then
					if [ "$KPORT" = "$port1" ]; then
						echo "Starting port" $port1 "timer"
						logger -t "knock.sh" "Starting port" $port1 "timer"
						/opt/sbin/screen -S knock_$port1 -X quit > /dev/null
						/opt/sbin/screen -dmS knock_$port1 sleep $DOUBLE_KNOCK_WAIT
						break
					fi
					if [ -n "$(ps -w | grep [k]nock_"$port1")" ]; then
						echo "Port" $port1 "timer running"
						logger -t "knock.sh" "Port" $port1 "timer running"
						port=$port2
					else
						break
					fi
				else
					port=$port1
				fi
				if [ "$KPORT" = "$port" ]; then
					echo "Executing command:" "$cmd"
					logger -t "knock.sh" "Executing command:" "$cmd"
					sh -c "eval $cmd &"
				fi
			fi
		done < $cf

		sleep $INTERVAL
		sleep $INTERVAL
		DATA=$(readDATA)
		oldID=$(readID)
	fi
done
