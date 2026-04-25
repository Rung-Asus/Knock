#!/bin/sh
#
#Knock.sh: Router Commands for non-admin users
#
#To install:
#        1) Move script to /jffs/scripts/ directory
#        2) Run 'sh /jffs/scripts/knock.sh -install'
#	 3) Follow install prompts to edit config and start knock background process
#        3A) -or- Manually update knock.cfg configuration file in the /jffs/addons/knock.d/ folder
#                Format of file is:
#                Port Number <space> Interface(s) [comma separated] <space> Command to execute [to end of line]
#                Default configuration file has use-case examples:
#                        Wake PC, reboot router, and run custom enable/disable scripts (e.g. for VPN Director rules)
#        4A) Run 'knock -start'
#
#Users can now execute commands by sending port knocks
#        (e.g. for main lan interface command, enter browser url: http://192.168.50.1:44444)
#
#To update configuration:
#        Run 'knock -stop'
#        Run 'knock -edit'
#         -or- Manually update /jffs/addons/knock.d/knock.cfg
#        Run 'knock -start'
#
#To display current installation and run status:
#        Run 'knock -status'
#
#To display current configuration file information:
#        Run 'knock -config'
#
#To update to the lastest version of script:
#        Run 'knock -update'
#
#To uninstall:
#        Run 'knock -uninstall'
#
#Main menu:
#	Run 'knock'
#
#Many thanks to @Viktor Jaep for all his help, input and testing of this script!
#Some concepts in this script were derved from @Viktor Jaep's awesome Tailmon script
#Original concept credit to @RMerlin (https://www.snbforums.com/threads/wake-on-lan-per-http-https-script.7958/post-47811)
# Last Updated: 25APR2026

#Update Log:
# 1.3
# - Fix for updated screen command
# 1.4
# - Added git branch swithing for update command (knock -develop or knock -main)
# 2.0
# - Added profile.add alias for knock
# - Added -status command (shows version, installed status, and run status)
# - Added optional install of screen utility as part of installation process
# - Added -edit command to edit the config file with a miniture embedded line editor
# - Updated installation with guided actions including editing config & starting background process
# - Improved visuals, progress feedback, & error checking
# - Added an SSH UI with install, configure, and uninstall functions (and more). "e" = Exit
# - Moved "REV" to "version" variable to be compatible with amtm

version=2.0b
REV=$version

INTERVAL=5
DOUBLE_KNOCK_WAIT=30

fn=$(readlink -f "$0")
jf="/jffs"
id=$jf"/addons/knock.d"
cf=$id"/knock.cfg"
tf="/tmp/knock.cfg"
vf=$id"/version.txt"
js=$jf"/scripts"
sf=$js"/knock.sh"
pm=$js"/post-mount"
fs=$js"/firewall-start"
pa=$jf"/configs/profile.add"
giturl="https://raw.githubusercontent.com/Rung-Asus/Knock/main"
giturld="https://raw.githubusercontent.com/Rung-Asus/Knock/develop"
df=$id/"develop"

#Fixes for new version of Screen
# credit to Tailmon and Martinski W.
unset LD_LIBRARY_PATH
[ "$HOME" != "/root" ] && export HOME="/root"
export SCREENDIR="${HOME}/.screen"

stty_save=$(stty -g)					#Save tty settings (e.g. blocking input)
trap cleanup HUP INT QUIT TERM				#Trap exit to restore tty to normal
#set -x

function banner {
echo " _                      _           _     "
echo "| | __ _ __   ___   ___| | __   ___| |__  "
echo "| |/ /| '_ \ / _ \ / __| |/ /  / __| '_ \ "
echo "|   < | | | | (_) | (__|   <  _\__ \ | | |"
echo "|_|\_\|_| |_|\___/ \___|_|\_\(_)___/_| |_| v"$REV
echo "                                          "
}

function cleanup {
#Trap exit to restore tty to normal
	stty $stty_save
	clear
	banner
	echo -e "\nExiting..."
	exit 1
}

###############################################
# Rung's tiny line editor
#
function editline {
#
#Input:
#	$header = Text in front of edit line
#	$st = current data in edit string
#Output:
#	$st = user edited version of string
#	$keypress2 = exit key (currently only
#           "<ENT>" = enter will exit editting)
#
#Note: $st should only a single line of ascii
# characters w/o control charaters (tabs will
# be converted to spaces)

left="\x08"		#Cursor left 1
right="\e[C"		#Cursor right 1
clearline="\e[K"	#Clear line at cursor
savecursor="\e[s"	#Save current cursor position
restorecursor="\e[u"	#Restore current cursor position
startline="\x0d"	#Move to start of line
rightcursor1="\e["	#Cursor right x (start)
rightcursor2="C"	#Cursor right x (end)
moreright="\e[7m>\e[0m"	#Inverse ">"
moreleft="\e[7m<\e[0m"	#Inverse "<"


function keypress2 {
#Assumes inptut blocking has been disabled ('stty -echo -icanon -icrnl time 0 min 0')
#Scans keyboard and returns immediately if nothing is pressed
#
#Output:
#	return code = number of characters returned (0 = no key press)
#	$keypress = raw undecoded key data
#	$keypress2 = character entered or ascii representation of entered control code (size > 1)

	keypress=$(cat)
	if  [ ${#keypress} -eq 0 ]; then
		return 0
	fi

	d=$(printf "%d" "'$keypress")
	case $d in
	 9) keypress2="<TAB>";;
	 13) keypress2="<ENT>";;
	 27) case ${keypress:1} in
		 [A) keypress2="<UP>";;
		 [B) keypress2="<DN>";;
		 [C) keypress2="<RT>";;
		 [D) keypress2="<LF>";;
		 [F) keypress2="<END>";;
		 [H) keypress2="<HM>";;
		 [2~) keypress2="<INS>";;
		 [3~) keypress2="<DEL>";;
		 [5~) keypress2="<PGU>";;
		 [6~) keypress2="<PGD>";;
		 *) keypress2="^["${keypress:1};;
		esac;;
	 [1-8] | 1[0-9] | 2[0-6]) keypress2='^'$(printf "\x$(printf %x $((64+$d)))");;
	 29) keypress2="^]"${keypress:1};;
	 30) keypress2="^^"${keypress:1};;
	 31) keypress2="^_"${keypress:1};;
	 127) keypress2="<BCK>";;
	 *) keypress2=$keypress;;
 	esac
	return ${#keypress2}
}

function refresh {
#Refreshes the current edit line with cursor, header, and "more" arrows
#Input:
#	header = string displayed before edit line
#	st = edit string
#	offset = buffer offset within st (0 = start of st)
#	pos = cursor postion in buffer
#	bufsize = maximum size of edit buffer (must be less then console width/header/more cursors)
#Output:
#	buf = updated buffer

	buf="${st:$offset:$bufsize}"
	echo -ne $startline$clearline
	echo -n "$header"
	if [ $offset -eq 0 ]; then
		echo -n " "
	else
		echo -ne $moreleft
	fi
	echo -ne $savecursor
	echo -n "$buf"

	if [ $((${#st}-$offset)) -gt $bufsize ]; then
		echo -ne $moreright
	fi
	echo -ne $restorecursor
	if [ $pos -gt 0 ]; then
		echo -ne $rightcursor1$pos$rightcursor2
	fi
}

#Start of editline function execution

 $(stty -echo -icanon -icrnl time 0 min 0)	#Read keyboard without blocking
 st="$(echo "$st" | sed 's/\t/     /')"	#Remove any tabs from input string
 cols=$(stty size | awk '{print $2}') 	#Console width
 bufsize=$((cols-${#header}-10)) 	#Line buffer size
 offset=0 				#Initial offset from edit string to buffer
 pos=0 					#Initial cursor position in buffer

 refresh				#display header and edit string

 while [ true ]; do
 #set +x
	while [ true ]; do
		keypress2 || break
	done
 #set -x

	case "$keypress2" in
	 "<ENT>")
		echo ""
		break;;
	 "<END>")
		pos=$((${#buf}))
		if [ $((${#st}-$offset)) -gt $bufsize ]; then
			offset=$((${#st}-$bufsize))
		fi
		refresh;;
	 "<HM>")
		pos=0
		offset=0
		refresh;;
	 "<RT>")
		if [ $pos -eq $bufsize ]; then
			offset=$((offset + 1))
			pos=$((pos - 1))
			refresh
		fi
		if [ $pos -lt ${#buf} ]; then
			echo -ne $right
			pos=$((pos+1))
		fi;;
	 "<LF>")
		if [ $pos -gt 0 ]; then
			echo -ne $left
			pos=$((pos-1))
		elif [ $offset -ne 0 ]; then
			offset=$((offset - 1))
			refresh
		fi;;
	 "<DEL>")
		if [ $pos -eq $bufsize ]; then
			offset=$((offset + 1))
			pos=$((pos - 1))
			refresh
		fi
		if [ $pos -lt ${#buf} ]; then
			buf="${st:$offset:$((bufsize+1))}"
			echo -ne $savecursor$clearline
			echo -n "${buf:$((pos+1))}"
			st="${st:0:$((offset+pos))}""${st:$((offset+pos+1))}"
			buf="${st:$offset:$bufsize}"
			if [ $((${#st}-$offset)) -gt $bufsize ]; then
				echo -ne $moreright
			fi
			echo -ne $restorecursor
		fi;;
	 "<BCK>")
		if [ $pos -eq 0 ] && [ $offset -ne 0 ]; then
			offset=$((offset - 1))
			pos=1
			refresh
		fi
		if [ $pos -gt 0 ]; then
			buf="${st:$offset:$((bufsize+1))}"
			echo -ne $left$savecursor$clearline
			echo -n "${buf:$pos}"
			st="${st:0:$((offset+pos-1))}""${st:$((offset+pos))}"
			buf="${st:$offset:$bufsize}"
			pos=$((pos-1))
			if [ $((${#st}-$offset)) -gt $bufsize ]; then
				echo -ne $moreright
			fi
			echo -ne $restorecursor
		fi;;
	 *)
		if [ ${#keypress2} -eq 1 ]; then
			if [ $pos -eq $bufsize ]; then
				offset=$((offset + 1))
				pos=$((pos - 1))
				refresh
			fi
			mr=$(( ${#buf} == $bufsize ? 1 : 0 ))
			buf="${st:$offset:$((bufsize-1))}"
			echo -n "$keypress2"
			echo -ne $savecursor$clearline
			echo -n "${buf:$pos}"
			if [ $mr -eq 1 ]; then
				echo -ne $moreright
			fi
			echo -ne $restorecursor
			st="${st:0:$((offset+pos))}""$keypress2""${st:$((offset+pos))}"
			buf="${st:$offset:$bufsize}"
			pos=$((pos+1))
		fi;;
	esac

 done

 stty $stty_save	#Reset tty to original (e.g. blocking input)
 return 0
}
###############################################

function promptyn {
	#Y/N prompt (credit Tailmon.sh)
	while true; do
		read -p "$1" -n 1 -r yn
		case "${yn}" in
			[Yy]* ) return 0 ;;
			[Nn]* ) return 1 ;;
			* ) echo -e "\nPlease answer y or n.";;
		esac
	done }

function checkinstall {
	#Verify everything is in its place
	[ -f $sf ] || return 1
	[ -f "/opt/sbin/screen" ] || return 1
	[ -f $cf ] || return 1
	[ -f $pm ] || return 1
	$(grep -q "knock.sh" $pm) || return 1
	[ -f $fs ] || return 1
	$(grep -q "knock.sh" $fs) || return 1
	[ -f $pa ] || return 1
	$(grep -q "knock.sh" $pa) || return 1
	return 0; }


function runstatus {
	#Verify knock rules are in iptables and knock.sh is running
	$(iptables -L INPUT | grep -q "knock.sh") || return 1
	$(/opt/sbin/screen -ls knock >/dev/null )  || return 1
	return 0; }


function showstatus {
	dashes=$(head -c 48 < /dev/zero | tr '\0' '-')
	echo $dashes
	checkinstall && echo -e "| Install Status: Installed\t\t\t|" || echo -e "| Install Status: Knock not properly installed!\t|"
	echo $dashes
	runstatus && echo -e "|     Run Status: Running & waiting for knocks\t|" || echo -e "|     Run Status: Knock STOPPED\t\t\t|"
	echo $dashes
	return
}

if [ "$1" = "-status" ]; then
		clear
		banner
		showstatus
		exit
fi

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

if [ "$1" = "-config" ]; then
	if [ ! -f $cf ]; then
		echo "Error: Missing configuration file" $cf
		exit 1
	fi
	clear
	banner
	showconfig
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
	sleep 2  #wait for any aborts
	runstatus && exit 0 || exit 1
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

	cm="\xE2\x9C\x94"

	if [ "$2" = "" ]; then
		clear
		banner
		if ! promptyn "Proceed with installing knock? (y/n):" ; then
			echo -e "\nThanks for trying knock.sh!"
			exit
		fi

		echo ""
		echo "Installing knock.sh..."
	fi

	#Check run location
	if [ "$fn" != "$sf" ]; then
		echo "Error: This script must be run from" $js
		exit 1
	fi
	chmod 755 $sf

	#Check entware
	echo -ne "\tChecking for Entware..."
	if [ ! -f "/opt/bin/opkg" ]; then
		echo -e "\nError: Knock.sh requires Entware. Please install Entware using the 'amtm' utility."
		exit 1
	fi
	echo -e $cm

	#Check screen, optionally install
	echo -ne "\tChecking for Screen utility..."
	if [ ! -f "/opt/sbin/screen" ]; then

		echo ""
		echo -e "\nKnock.sh requires the Entware utility 'screen'"

		if  promptyn "Proceed with installing 'screen'? (y/n):" ; then
			echo ""
			opkg install screen
			if [ ! -f "/opt/sbin/screen" ]; then
				echo "Entware screen install failed"
				exit 1
			fi
		else
			echo ""
			echo "Cancelling install"
			exit 1
		fi
		echo -ne "\tScreen successfully installed."
	fi
	echo -e $cm

	#Setup config file
	echo -ne "\tChecking config file..."
	if [ ! -d $jf"/addons" ]; then
		echo -e "\nError: This script is designed for Asuswrt-Merlin firmware only"
		exit 1
	fi
	mkdir $id 2>/dev/null
	echo -e $cm

	if [ ! -f $cf ]; then
		echo -ne "\tCreating config file..."

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

		echo -e $cm

		if [ "$2" = "" ]; then
		 #Optionally restore saved config file, if it exists
		 if [ -f $tf ]; then
			echo -ne "\t"
			if  promptyn "Restore saved config file ("$tf")? (y/n):" ; then
				echo -en "\n\tRestoring saved file..."
				cp $tf $cf
				echo -e $cm
			else
				echo -e "\n\tKeeping default file."
			fi
		 fi
		fi
	fi

	#Add post-mount command
	echo -ne "\tUpdating post-mount file..."
	if ! [ -f $pm ]; then
		echo "#!/bin/sh" > $pm
      		echo "" >> $pm
		chmod 755 $pm
	fi
	sed -i -e '/knock.sh/d' $pm
	echo "(sleep 30 &&" $sf "-screen) & # Added by knock.sh" >> $pm
	echo -e $cm

	#Add firewall-start command
	echo -ne "\tUpdating firewall-start file..."
	if ! [ -f $fs ]; then
		echo "#!/bin/sh" > $fs
      		echo "" >> $fs
		chmod 755 $fs
	fi
	sed -i -e '/knock.sh/d' $fs
	echo $sf "-firewall # Added by knock.sh" >> $fs
	echo -e $cm

	#add profile.add command
	echo -ne "\tUpdating profile.add file..."
	if ! [ -f $pa ]; then
		touch $pa
	fi
	sed -i -e '/knock.sh/d' $pa
	echo "alias knock=\"sh" $sf"\" # Added by knock.sh" >> $pa
	echo -e $cm

	if [ "$2" = "" ]; then
		echo ""
		echo "Knock.sh Rev" $REV "successfully installed!"
		echo ""
		if  promptyn "Would you like to edit the config file now ("$cf")? (y/n):" ; then
			echo ""
			$sf -edit -nobanner
			if  promptyn "Are you ready to start processing knocks (start knock.sh)? (y/n):" ; then
				echo ""
				$sf -start
			else
				echo -e "\nWhen ready, please run 'knock -start'"
			fi
		else
			echo -e "\nPlease update the configuration file from the default ('knock -edit')"
			echo ""
			echo "Once updated, please run 'knock -start' to begin processing knocks"
		fi
	fi
	exit
fi

if [ "$1" = "-start" ] || [ "$1" = "-restart" ]; then
	if [ ! -f $cf ]; then
		echo "Error: Missing configuration file" $cf
		exit 1
	fi

	service restart_firewall >/dev/null

	echo "Starting knock.sh background process..."

	if $sf "-screen"; then
		if [ "$2" = "" ]; then
			clear
			banner
			echo "Knock.sh started and ready for port knocks"
			echo ""
			showconfig
		fi
	else
		echo "Error: Cannot start knock in background"
		exit 1
	fi
	exit
fi

if [ "$1" = "-stop" ]; then
	screen -S knock -X quit > /dev/null
	if [ "$2" = "" ]; then
		clear
		banner
	fi
	echo "knock.sh stopped"
	exit
fi

if [ "$1" = "-uninstall" ]; then

	clear
	banner
	if ! promptyn "Proceed with uninstalling knock? (y/n):" ; then
		echo ""
		echo -e "\nExiting uninstallation"
		exit
	fi
	echo ""

	screen -S knock -X quit > /dev/null
	sed -i -e '/knock.sh/d' $pm	#remove post-mount command
	sed -i -e '/knock.sh/d' $fs	#remove firewall-start command
	sed -i -e '/knock.sh/d' $pa	#remove profile.add command

	service restart_firewall >/dev/null #Remove iptable modifications

	rm $sf #Remove script file
	cp $cf $tf #Save config in temp folder
	rm $cf #Remove config fire
	rm $vf 2> /dev/null #Remove version file
	rm $df 2> /dev/null #Remove develop flag

	#Attempt to remove installation directory
	if [ $(pwd) = $id ]; then
		echo "Error: cannot remove install directory" $id
	else
		rmdir $id 2>/dev/null
	fi

	echo ""
	echo "Knock.sh uninstalled"
	echo "Existing configuration file saved as" $tf
	echo "Thanks for using knock.sh!"
	exit
fi

if [ "$1" = "-develop" ]; then
        touch $df
	exit
fi

if [ "$1" = "-main" ]; then
        rm $df 2> /dev/null
	exit
fi

function updatecommand {
	clear
	banner

	if [ -f $df ]; then
		echo "On develop branch."
		giturl=$giturld
	fi

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
			$sf -install -force
			echo "Restarting..."
			$sf -start -nobanner
			echo "Update completed."
			echo ""
			echo -e "Knock version:\t"$REV
			showstatus
			echo ""
			showconfig
		else
			echo -e "\nNo update performed"
			return 1
		fi
	else
		echo "Error: network issue"
		return 1
	fi
	return 0
}

if [ "$1" = "-update" ]; then
	updatecommand
	exit
fi

function editcommand {
	function editknockentry {
		#Edit comment
		st="$comment"
		header="     Comment:"
		editline
		comment="$st"

		#Edit ports
		st=$ports
		header="     Port(s):"
		editline
		st=${st// /}
		allgood=1
		for port in ${st//,/ }; do
			if [ $port -gt 0 -a $port -le 65535 ] 2> /dev/null; then
				continue
			else
				allgood=0
			fi
		done
		if [ $allgood -eq 1 ]; then
			ports=$st
		else
			echo "Error! '"$st"' is an invalid port list. Changes not saved."
		fi

		#Edit interfaces
		st=$interfaces
		header="Interface(s):"
		editline
		st=${st// /}
		allgood=1
		for interface in ${st//,/ }; do
			$(ifconfig $interface >/dev/null 2>&1) || allgood=0
		done
		if [ $allgood -eq 1 ]; then
			interfaces=$st
		else
			echo "Error! '"$st"' is an invalid interface list. Changes not saved."
		fi

		#Edit command
		st="$cmd"
		header="     Command:"
		editline
		cmd="$st"
	}

	#Read configuration file into virtual array
	lastcomment=""
	commandnum=0
	updated=0
	while read ports interfaces cmd; do
		if [ -n "$ports" ]; then
			if [ $(echo $ports | cut -c 1-1) != "#" ]; then
				#Not a command line
				commandnum=$((commandnum+1))

				#Load data into pseudo array
				eval comment$commandnum=\"$lastcomment\"
				eval ports$commandnum=\"$ports\"
				eval interfaces$commandnum=\"$interfaces\"
				eval cmd$commandnum=\"$cmd\"
			else
				#Commment line
				lastcomment=$(echo "$ports $interfaces $cmd" | cut -c 2-)
			fi
		fi
	done < $cf
	commandcount=$commandnum

	#Edit menu loop
	while [ true ]; do
		clear
		cols=$(stty size | awk '{print $2}') #Console width
		dashes=$(head -c $cols < /dev/zero | tr '\0' '-')
		{
			echo -e "The following ports/interfaces will execute these router commands:\n"
			commandnum=0

			#Display virtual array
			while [ $commandnum -lt $commandcount ]; do
				commandnum=$((commandnum+1))
				echo $dashes
				echo "Command #" $commandnum
				comment="$(eval echo \"\$comment$commandnum\")"
				ports=$(eval echo \"\$ports$commandnum\")
				interfaces=$(eval echo \"\$interfaces$commandnum\")
				cmd=$(eval echo \"\$cmd$commandnum\")

				echo -en "\t"
				echo $comment
				echo -e "\tPort" $ports "on" $interfaces
				echo -en "\t"
				echo "Command:" "$cmd"
				interface=$(echo $interfaces | awk -F',' '{print $1}')

				#Display URLs (if valid interface)
				if  $(ifconfig $interface >/dev/null 2>&1); then
					port1=$(echo $ports | awk -F',' '{print $1}')
					echo -e "\tURL to initiate command:" $(ifconfig  $interface | awk '{print $2}' | grep addr | sed 's/addr:/http:\/\//g')":"$port1
					port2=$(echo $ports | awk -F',' '{print $2}')
					if [ -n "$port2" ]; then
						echo -e "\t\tWait" $(( $INTERVAL * 3 )) "seconds then URL to complete command:" $(ifconfig  $interface | awk '{print $2}' | grep addr | sed 's/addr:/http:\/\//g')":"$port2
					fi
				else
					echo $interface "is an invalid interface!"
				fi
				echo ""
			done
			echo $dashes
		} > /tmp/knock.txt

		more /tmp/knock.txt #Using "more" command for long config files

		read -p "(E)dit command, (A)dd command, (D)elete command, or (Q)uit editing? (e,a,d,q): " SelectEdit

		case $SelectEdit in
		 [Aa])
			#Add command
			commandnum=$commandcount
			comment="Example comment"
			ports=44444
			interfaces="br0"
			cmd="ls #example command"
			if [ $commandnum -ne 0 ]; then
				ports=$(eval echo \"\$ports$commandnum\")
				ports=$((ports+1))
				comment="$(eval echo \"\$comment$commandnum\")"
				interfaces=$(eval echo \"\$interfaces$commandnum\")
				cmd=$(eval echo \"\$cmd$commandnum\")
			fi
			commandnum=$((commandnum+1))
			commandcount=$commandnum

			echo "Adding new Command #" $commandnum
			echo ""
			editknockentry
			echo ""
			echo -n "Save changes to port knock entry? (y=Yes, n=No):"
			if promptyn ; then
				eval comment$commandnum=\"$comment\"
				eval ports$commandnum=\"$ports\"
				eval interfaces$commandnum=\"$interfaces\"
				eval cmd$commandnum=\"$cmd\"
				updated=1
			else
				commandcount=$((commandcount-1))
			fi
			;;

		 [Dd])
			#Delete command
			while [ true ]; do
				echo ""
				echo -n "Enter command number to delete (1 to" $commandcount"): "
				read -p "" commandnum
				if [ $commandnum -gt 0 -a $commandnum -le $commandcount ] 2> /dev/null; then
					break
				fi
			done
			echo ""
			echo -n "Delete knock entry #" $commandnum "? (y=Yes, n=No): "
			if promptyn ; then
				while [ $commandnum -lt $commandcount ]; do
					commandnumold=$((commandnum+1))
					comment="$(eval echo \"\$comment$commandnumold\")"
					ports=$(eval echo \"\$ports$commandnumold\")
					interfaces=$(eval echo \"\$interfaces$commandnumold\")
					cmd=$(eval echo \"\$cmd$commandnumold\")
					eval comment$commandnum=\"$comment\"
					eval ports$commandnum=\"$ports\"
					eval interfaces$commandnum=\"$interfaces\"
					eval cmd$commandnum=\"$cmd\"

					commandnum=$commandnumold
				done
				commandcount=$((commandcount-1))
				updated=1
			fi
			;;

		 [Ee])
			#Edit command
			while [ true ]; do
				echo ""
				echo -n "Enter command number to edit (1 to" $commandcount"): "
				read -p "" commandnum
				if [ $commandnum -gt 0 -a $commandnum -le $commandcount ] 2> /dev/null; then
					break
				fi
			done
			comment="$(eval echo \"\$comment$commandnum\")"
			ports=$(eval echo \"\$ports$commandnum\")
			interfaces=$(eval echo \"\$interfaces$commandnum\")
			cmd=$(eval echo \"\$cmd$commandnum\")
			clear
			echo "Editing Command #" $commandnum
			echo ""
			echo -en "\t"
			echo $comment
			echo -en "\t"
			echo "Port" $ports "on" $interfaces
			echo -en "\t"
			echo "Command:" "$cmd"
			echo $dashes
			echo ""
			editknockentry
			echo -n "Save changes to port knock entry? (y=Yes, n=No):"
			if promptyn ; then
				eval comment$commandnum=\"$comment\"
				eval ports$commandnum=\"$ports\"
				eval interfaces$commandnum=\"$interfaces\"
				eval cmd$commandnum=\"$cmd\"
				updated=1
			fi
			;;

		 [Qq]) break;;
		esac
	done

	echo ""
	if [ $updated -eq 1 ]; then
		echo -n "Save changes to config file? (y=Yes, n=No):"
		if promptyn ; then
			echo -en "\nSaving configuration"

			echo "#knock.sh configuration file" > $cf
			echo -e "\n#Format Port Number <space> Interface(s) [comma separated] <space> Command to execute [to end of line]\n" >> $cf

			#Write virtual array back to config file
			commandnum=0
			while [ $commandnum -lt $commandcount ]; do
				commandnum=$((commandnum+1))
				echo -n "..."$commandnum
				echo "$(eval echo \"#\$comment$commandnum\")" >> $cf
				echo $(eval echo \"\$ports$commandnum \$interfaces$commandnum \$cmd$commandnum\") >> $cf
				echo "" >> $cf
			done
			echo -e "\n\nNew config file:"
			echo $dashes
			more $cf
			echo $dashes
			echo -n "Press any key to continue..."
			read -n 1 -r yn
			echo ""
		else
			echo ""
		fi
	fi

	if [ "$2" = "" ]; then
		clear
		banner
		echo "Thanks for using knock.sh!"
	fi
	return
}

if [ "$1" = "-edit" ]; then
	editcommand "-edit" $2
	exit
fi


if [ "$1" = "" ]; then

	#Main menu loop
	while [ true ]; do
		clear
		banner

		#dashes=$(head -c 113 < /dev/zero | tr '\0' '-')
		#echo $dashes
		#checkinstall && echo -en "|\tInstall Status: Installed\t\t\t" || echo -en "|\tInstall Status: Knock not properly installed!\t"
		#echo -en "|\t"
		#runstatus && echo -en "Run Status: Running & waiting for knocks\t" || echo -en "Run Status: Knock STOPPED\t\t\t"
		#echo -e "|\n"$dashes
		showstatus

		echo ""
		echo "Main Menu"
		echo "========="
		echo ""
		echo "1. Install/reinstall knock.sh"
		echo "2. Uninstall knock.sh"
		if checkinstall ; then
			echo "3. Display knock.sh config file"
			echo "4. Start/restart knock.sh background process"
			echo "5. Stop knock.sh background process"
			echo "6. Edit knock.sh config file"
			echo "7. Update script to latest version and exit"
		fi
		echo ""
		echo "e. Exit"
		echo ""

		read -p "Enter selection: " SelectMenu

		case $SelectMenu in

		 [1])
			sh $sf -install -force
			$sf -stop -nobanner > /dev/null

			if checkinstall ; then
				if [ -f $tf ]; then
					echo -ne "\t"
					if  promptyn "Restore saved config file ("$tf")? (y/n):" ; then
						echo -en "\n\tRestoring saved file..."
						cp $tf $cf
						echo -e $cm
					else
						echo -e "\n\tKeeping default file."
					fi
				fi
				echo ""
				echo "Knock.sh Rev" $REV "successfully installed!"
				echo ""
				if  promptyn "Would you like to edit the config file now ("$cf")? (y/n):" ; then
					echo ""
					$sf -edit -nobanner
					if  promptyn "Are you ready to start processing knocks (start knock.sh)? (y/n):" ; then
						echo ""
						$sf -start -nobanner
					else
						echo ""
						echo "When ready, please run start from main menu"
					fi
				else
					echo ""
					echo "Please edit the configuration file from main menu"
					echo ""
					echo "Once updated, please run choose start from the main menu to begin processing knocks"
				fi
			fi


			echo -n "Press any key to continue..."
			read -n 1 -r yn
			echo ""
			;;
		 [2])
			sh $sf -uninstall
			exit;;


		 [Ee]) break;;
		esac

		if checkinstall ; then
			case $SelectMenu in

		 	 [3])
				$sf -config
				echo -n "Press any key to continue..."
				read -n 1 -r yn
				echo ""
				;;
			 [4])
				$sf -start -nobanner
				echo -n "Press any key to continue..."
				read -n 1 -r yn
				echo ""
				;;
			 [5])
				$sf -stop -nobanner
				echo -n "Press any key to continue..."
				read -n 1 -r yn
				echo ""
				;;
			 [6])
				editcommand -edit -nobanner
				if [ $updated -eq 1 ]; then
					if  promptyn "Are you ready to start processing knocks (start knock.sh)? (y/n):" ; then
						echo ""
						$sf -start -nobanner
					else
						echo ""
						$sf -stop -nobanner
					fi
				fi
				echo -n "Press any key to continue..."
				read -n 1 -r yn
				echo ""
				;;
			 [7])
				if updatecommand; then
					echo "Type 'knock' to return to main menu"
					exit
				else
					echo -n "Press any key to continue..."
					read -n 1 -r yn
					echo ""
				fi
				;;
			esac
		fi
	done

	clear
	banner
	echo "Thanks for using knock.sh!"
	exit
fi


if [ "$1" != "-loop" ]; then
	echo "Knock.sh: Router Commands for non-admin users"
	echo "Version" $REV
	echo ""
	echo "To install:"
	echo -e "\t1) Move script to" $js"/ directory"
	echo "	2) Run 'sh" $sf "-install'"
	echo "	3) Follow install prompts to edit config and start knock background process -or-"
	echo "	3B) Manually update knock.cfg configuration file in the" $id"/ folder"
        echo "		Format of file is:"
        echo "		Port Number <space> Interface(s) [comma separated] <space> Command to execute [to end of line]"
	echo -e "\t\tDefault configuration file has use-case examples:"
	echo -e "\t\t\tWake PC, reboot router, and run custom enable/disable scripts (e.g. for VPN Director rules)"
	echo "	4B) Run 'knock -start'"
	echo ""
	echo "To update configuration:"
	echo "	Run 'knock -stop'"
	echo "	Run 'knock -edit' -or-"
	echo "	Manually update" $cf
	echo "	Run 'knock -start'"
	echo ""
	echo "To display current Knock status:"
	echo "	Run 'knock -status'"
	echo ""
	echo "To display current configuration file information:"
	echo "	Run 'knock -config'"
	echo ""
	echo "To update to the lastest version of script:"
	echo "	Run 'knock -update'"
	echo ""
	echo "To uninstall:"
	echo "	Run 'knock -uninstall'"
	echo ""
	echo "To display main menu:"
	echo "	Run 'knock'"
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
					if $(/opt/sbin/screen -ls knock_$port1 >/dev/null); then
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
