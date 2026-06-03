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
#-----------------------------------------------------------------------
# Last Updated: 2026-Jun-02
########################################################################

#Update Log:
# 1.3
# - Fix for updated screen command
# 1.4
# - Added git branch switching for update command (knock -develop or knock -main)
# 2.0
# - Added profile.add alias for knock
# - Added -status command (shows version, installed status, and run status)
# - Added optional install of screen utility as part of installation process
# - Added -edit command to edit the config file with a miniture embedded line editor
# - Updated installation with guided actions including editing config & starting background process
# - Improved visuals, progress feedback, & error checking
# - Added an SSH UI with install, configure, and uninstall functions (and more). "e" = Exit
# - Moved "REV" to "version" variable to be compatible with amtm
# - Added amtmupdate command
# 2.0.1
# - Fix for iphone packets having constant 0 ID
# 2.0.2
# - Fix for double knock early exit bug
# - Fix for packets without DF flag set
# 2.1.0
# - Prepare for Martinski merge
# - readonly constants, string definition quotes, function definition style, rearanged & renamed subroutines & variables
# - Added min knock port, changed fake ID
# - Merged Martinski interactive test, logger, mutex lock
# - Added force kill during restart (mutext lock), added knock log level
# - Merged Martinski ShowConfig, firewall code
# - Added new firewall check to ShowStatus for missing firewall rules

readonly version=2.1.0
readonly REV="$version"
readonly INTERVAL=5
readonly MIN_KNOCK_PORT=1024  #Avoid well-known RESERVED ports#
readonly DOUBLE_KNOCK_WAIT=30

#To handle ID field from iOS always being ZERO#
readonly FAKE_NUMID=65555   #Valid ID values are below 64K#
readonly FAKE_KMESG="knock.sh IN= OUT= MAC= SRC= DST= LEN= TOS= PREC= TTL= ID=$FAKE_NUMID PROTO="

# Give priority to built-in binaries #
export PATH="/bin:/usr/bin:/sbin:/usr/sbin:$PATH"

#-------------------------------------#
# Added by Martinski W. [2026-May-17] #
#-------------------------------------#
readonly scriptFileName="${0##*/}"
readonly scriptFNameTag="${scriptFileName%%.*}"
readonly logTagStr="${scriptFNameTag}_[$$]"
readonly pLogALERT=1
readonly pLogCRITC=2
readonly pLogERROR=3
readonly pLogWARNG=4
readonly pLogNOTIC=5
readonly pLogINFOR=6
readonly CLEARct="\e[0m"
readonly REDct="\e[1;31m"
readonly GREENct="\e[1;32m"
readonly YELLWct="\e[1;33m"
readonly ERRORct="$REDct"
readonly WARNGct="$YELLWct"

if [ -t 0 ] && ! tty | grep -qwi "NOT"
then
	readonly isInteractive=true
	readonly stty_save="$(stty -g)"   #Save settings (e.g. blocking input)#
else
	readonly isInteractive=false
fi

if [ "$isInteractive" = "false" ] && { [ $# -eq 0 ] || [ -z "$1" ] ; }
then
	logger -st "$logTagStr" -p 3 "**ERROR**: CLI Menu is NOT available in a non-interactive shell"
	exit 1
fi

fn="$(readlink -f "$0")"
jf="/jffs"
id="${jf}/addons/knock.d"
cf="${id}/knock.cfg"
tf="/tmp/knock.cfg"
ff1="/tmp/${scriptFNameTag}_iptables1.txt"
ff2="/tmp/${scriptFNameTag}_iptables2.txt"
vf="${id}/version.txt"
js="${jf}/scripts"
sf="${js}/knock.sh"
pm="${js}/post-mount"
fs="${js}/firewall-start"
pa="${jf}/configs/profile.add"
giturl="https://raw.githubusercontent.com/Rung-Asus/Knock/main"
giturld="https://raw.githubusercontent.com/Rung-Asus/Knock/develop"
df=$id/"develop"
cm="\xE2\x9C\x94"

#Fixes for new version of Screen
# credit to Tailmon and Martinski W.
unset LD_LIBRARY_PATH
[ "$HOME" != "/root" ] && export HOME="/root"
export SCREENDIR="${HOME}/.screen"

#----------------------------------------#
# Modified by Martinski W. [2026-May-17] #
#----------------------------------------#
#Trap exit to restore TTY#
trap 'CleanUp' HUP INT QUIT ABRT TERM

#set -x

banner()
{
	echo " _                      _           _     "
	echo "| | __ _ __   ___   ___| | __   ___| |__  "
	echo "| |/ /| '_ \ / _ \ / __| |/ /  / __| '_ \ "
	echo "|   < | | | | (_) | (__|   <  _\__ \ | | |"
	echo "|_|\_\|_| |_|\___/ \___|_|\_\(_)___/_| |_| v$REV"
	echo
}

#----------------------------------------#
# Modified by Martinski W. [2026-May-17] #
#----------------------------------------#
#Trap exit to restore tty to normal#
CleanUp()
{
	if [ -n "${stty_save:+xSETOKx}" ]
	then stty "$stty_save"
	fi
	clear
	banner
    _ReleaseMutexFLock_ checkLockOK
	printf "\nExiting...\n"
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
	echo -ne "$startline$clearline"
	echo -n "$header"
	if [ "$offset" -eq 0 ]; then
		echo -n " "
	else
		echo -ne "$moreleft"
	fi
	echo -ne "$savecursor"
	echo -n "$buf"

	if [ "$((${#st}-$offset))" -gt "$bufsize" ]; then
		echo -ne "$moreright"
	fi
	echo -ne "$restorecursor"
	if [ "$pos" -gt 0 ]; then
		echo -ne "$rightcursor1$pos$rightcursor2"
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

 while true ; do
 #set +x
	while true ; do
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

    if [ -n "${stty_save:+xSETOKx}" ]
    then stty "$stty_save"  #Reset to original (e.g. blocking input)#
    fi
    return 0
}
###############################################

#----------------------------------------#
# Modified by Martinski W. [2026-May-31] #
#----------------------------------------#
PromptYN()
{
	local yesORno  retCode=1  promptStr=""
	if [ $# -gt 0 ] && [ -n "$1" ]
	then promptStr="$1"
	fi

	while true
	do
		printf "$promptStr "
		read -r yesORno
		case "$yesORno" in
			[Nn]|No|no) yesORno=NO
				retCode=1
				break
				;;
			[Yy]|Yes|yes) yesORno=YES
				retCode=0
				break
				;;
			 *) printf "Please answer y or n"
				if [ -z "$promptStr" ]
				then printf ":"
				else printf "." ; echo
				fi
				;;
		esac
	done
	echo "$yesORno"
	return "$retCode"
}

#-------------------------------------#
# Added by Martinski W. [2026-May-31] #
#-------------------------------------#
_PressAnyKey_()
{
	! "$isInteractive" && return 0
	local promptStr
	if [ $# -gt 0 ] && [ -n "$1" ]
	then promptStr="$1"
	else promptStr="Press ANY key to continue..."
	fi
	printf "\n$promptStr"
	read -n1 -rs anyKEY ; echo
}

#-------------------------------------#
# Added by Martinski W. [2026-May-18] #
#-------------------------------------#
_LogMsg_()
{
    if [ $# -lt 1 ] || [ -z "$1" ]
    then return 1
    fi
    if [ $# -lt 2 ] || [ -z "$2" ] || \
       ! echo "$2" | grep -qE "^[1-6]$"
    then logPrioNum="$pLogNOTIC"
    else logPrioNum="$2"
    fi
    if "$isInteractive" && \
       { [ $# -lt 3 ] || [ "$3" != "NOECHO" ] ; }
    then
        if [ "$logPrioNum" -gt "$pLogWARNG" ]
        then printf "${1}\n"
        elif [ "$logPrioNum" -eq "$pLogWARNG" ]
        then printf "${WARNGct}${1}${CLEARct}\n"
        else printf "${ERRORct}${1}${CLEARct}\n"
        fi
    fi
    if [ $# -lt 3 ] || [ "$3" != "NOLOG" ]
    then
        logger -t "$logTagStr" -p "$logPrioNum" "$1"
    fi
}

#-------------------------------------#
# Added by Martinski W. [2026-May-31] #
#-------------------------------------#
readonly protoFLregex="[:](T(CP)?|U(DP)?)"
readonly portNUMregex="[1-9][0-9]{3,4}"
readonly portT01regex="${portNUMregex}:T"
readonly portU01regex="${portNUMregex}:U"
readonly portDEFregex="${portNUMregex}(${protoFLregex})?"

#-------------------------------------#
# Added by Martinski W. [2026-May-31] #
#-------------------------------------#
_GetTaggedPortNumber_()
{
    if [ $# -eq 0 ] || [ -z "$1" ] || \
       ! echo "$1" | grep -qE "^${portDEFregex}$" || \
       [ "$(echo "$1" | awk -F':' '{print $1}')" -gt 65535 ] || \
       [ "$(echo "$1" | awk -F':' '{print $1}')" -lt "$MIN_KNOCK_PORT" ]
    then
        echo "$1" ; return 1
    fi
    local portTMP

    while true
    do
        if echo "$1" | grep -qE "^${portNUMregex}$"
        then
            portTMP="${1}_TCP"
            break
        fi
        if echo "$1" | grep -qE "^${portT01regex}$"
        then
            portTMP="$(echo "$1" | sed 's/:T/_TCP/')"
            break
        fi
        if echo "$1" | grep -qE "^${portU01regex}$"
        then
            portTMP="$(echo "$1" | sed 's/:U/_UDP/')"
            break
        fi
        portTMP="$(echo "$1" | sed 's/:/_/')"
        break
    done

    echo "$portTMP"
    return 0
}

#-------------------------------------#
# Added by Martinski W. [2026-May-18] #
#-------------------------------------#
_ValidatePortNumber_()
{
    local logARG=""
    if [ $# -gt 1 ] && [ -n "$2" ] && \
       echo "$2" | grep -qE '^(NOLOG|silent)$'
    then logARG="$2"
    fi

    if [ $# -eq 0 ] || [ -z "$1" ] || \
       ! echo "$1" | grep -qE "^${portDEFregex}$" || \
       [ "$(echo "$1" | awk -F':' '{print $1}')" -gt 65535 ] || \
       [ "$(echo "$1" | awk -F':' '{print $1}')" -lt "$MIN_KNOCK_PORT" ]
    then
        [ "$logARG" != "silent" ] && \
        _LogMsg_ "**ERROR**: INVALID port number [$1]" "$pLogERROR" "$logARG"
        return 1
    fi
    return 0
}

#-------------------------------------#
# Added by Martinski W. [2026-May-31] #
#-------------------------------------#
_CheckInterface_()
{
    local logARG=""
    if [ $# -gt 1 ] && [ -n "$2" ] && \
       echo "$2" | grep -qE '^(NOLOG|silent)$'
    then logARG="$2"
    fi

    if [ $# -eq 0 ] || [ -z "$1" ] || \
       ! ifconfig "$1" >/dev/null 2>&1
    then
        [ "$logARG" != "silent" ] && \
        _LogMsg_ "*WARNING*: Interface [$1] is currently INACTIVE" "$pLogWARNG" "$logARG"
        return 1
    fi
    return 0
}

#-------------------------------------#
# Added by Martinski W. [2026-May-31] #
#-------------------------------------#
_Get_IFace_IPAddress_()
{
	if [ $# -eq 0 ] || [ -z "$1" ] ; then echo "ERROR" ; return 1 ; fi
	ifconfig "$1" | awk '{print $2}' | grep 'addr:' | awk -F':' '{print $2}'
}

#-------------------------------------#
# Added by Martinski W. [2026-May-31] #
#-------------------------------------#
_NormalizeCSVList_()
{
	if [ $# -eq 0 ] || [ -z "$1" ] ; then echo ; return 1 ; fi
	echo "$1" | sed 's/^ *//; s/ *$//; s/^,*//; s/,*$//; s/,,\+/,/g'
}

#----------------------------------------#
# Modified by Martinski W. [2026-May-31] #
#----------------------------------------#
#Verify everything is in its place#
CheckInstall()
{
	[ -s "$sf" ] || return 1
	[ -x /opt/sbin/screen ] || return 1
	[ -s "$cf" ] || return 1
	[ -s "$pm" ] || return 1
	grep -q "knock.sh" "$pm" || return 1
	[ -s "$fs" ] || return 1
	grep -q "knock.sh" "$fs" || return 1
	[ -s "$pa" ] || return 1
	grep -q "knock.sh" "$pa" || return 1
	return 0
}

#Verify knock rules are in firewall and knock.sh is running#
CheckStatus()
{
	iptables -S INPUT | grep -q '\bknock.sh' || return 1
	/opt/sbin/screen -ls knock >/dev/null || return 1
	return 0
}

#----------------------------------------#
# Modified by Martinski W. [2026-Jun-01] #
#----------------------------------------#
#Verify no missing firewall rules
CheckFirewall()
{
	local fullPortLIST=""  dupPortLIST=""
	local portIFacesLst  portNumSeqLst  portListCount
	local activeIFaceOK  portNumOK  pIFace  pNumber
	local tempFWR="/tmp/var/${scriptFNameTag}_FWRules.TMP"

	if ! _CheckConfigurationFile_ silent
	then return 1
	fi

	#Save current firewall knock rules#
	iptables -S INPUT | grep '\bknock.sh' > "$ff1"

	printf '' > "$ff2"
	printf '' > "$tempFWR"

	#Recreate rules from config file#
	while read -r cfgLINE
	do
		if [ -z "$cfgLINE" ] || \
		   echo "$cfgLINE" | grep -qE "^[[:blank:]]*[#].*"
		then continue  #SKIP#
		fi
		cfgLINE="$(echo "$cfgLINE" | sed 's/  \+/  /')"
		thePORTS="$(echo "$cfgLINE" | awk -F' ' '{print $1}')"
		theIFACE="$(echo "$cfgLINE" | awk -F' ' '{print $2}')"
		theCMDx="$(echo "$cfgLINE" | awk -F' ' '{match($0, $3); print substr($0, RSTART)}')"

		if [ -z "$thePORTS" ] || [ -z "$theIFACE" ] || [ -z "$theCMDx" ]
		then continue  #INVALID#
		fi

		thePORTS="$(_NormalizeCSVList_ "$thePORTS")"
		theIFACE="$(_NormalizeCSVList_ "$theIFACE")"
		portIFacesLst="$(echo "$theIFACE" | tr ',' ' ')"
		portNumSeqLst="$(echo "$thePORTS" | tr ',' ' ')"
		portListCount="$(echo "$thePORTS" | awk -F',' '{print NF}')"
		activeIFaceOK=true ; portNumOK=true

		for IFace in $portIFacesLst
		do
			if ! _CheckInterface_ "$IFace" silent
			then activeIFaceOK=true   #Allow FW Rule for INACTIVE IFace??#
			fi
		done

		for pNumber in $portNumSeqLst
		do
			if ! _ValidatePortNumber_ "$pNumber" silent
			then portNumOK=false
			fi
			if _CheckDupPortFound_ "$pNumber" silent
			then portNumOK=false
			fi
		done

		if [ "$portNumOK" = "false" ] || \
		   [ "$activeIFaceOK" = "false" ] || \
		   [ "$portListCount" -gt 2 ]
		then continue  #INVALID#
		fi

		for thePort in $portNumSeqLst
		do
			portN="$(echo "$thePort" | awk -F':' '{print $1}')"
			proto="$(echo "$thePort" | awk -F':' '{print $2}')"

			if [ -z "$proto" ] || [ "$proto" = "T" ]
			then proto="tcp"
			elif [ "$proto" = "U" ]
			then proto="udp"
			else proto="$(echo "$proto" | tr 'UDTCP' 'udtcp')"
			fi

			for IFace in $portIFacesLst
			do
			{
			    echo "-A INPUT -i $IFace -p $proto -m $proto --dport $portN -j LOG --log-prefix \"knock.sh \" --log-level 6"
			} >> "$tempFWR"
			done
		done
	done < "$cf"

	#FW Rules in REVERSE order for comparison#
	awk '{lines[NR]=$0} END {for (idx=NR; idx>0; idx--) print lines[idx]}' "$tempFWR" > "$ff2"
	rm -f "$tempFWR"

	#Files should match#
	if cmp -s "$ff1" "$ff2"
	then return 0
	else return 1
	fi
}

#----------------------------------------#
# Modified by Martinski W. [2026-Jun-01] #
#----------------------------------------#
ShowStatus()
{
	dashes="$(head -c 48 < /dev/zero | tr '\0' '-')"
	printf "${dashes}\n"
	printf "| Knock.sh: Router Commands for non-admin users\t|\n"
	printf "${dashes}\n"
	if CheckInstall
	then
		printf "| Install Status: ${GREENct}Installed${CLEARct}\t\t\t|\n"
	else
		printf "| Install Status: ${REDct}Knock not properly installed${CLEARct}\t|\n"
	fi
	printf "${dashes}\n"
	if CheckStatus
	then
		printf "|     Run Status: ${GREENct}Running & waiting for knocks${CLEARct}\t|\n"
	else
		printf "|     Run Status: Knock ${REDct}STOPPED${CLEARct}\t\t\t|\n"
	fi
	printf "${dashes}\n"
	if CheckFirewall
	then
		printf "|Firewall Status: ${GREENct}All rules in place${CLEARct}\t\t|\n"
	else
		printf "|Firewall Status: ${REDct}MISSING RULE${CLEARct}. RESTART knock!\t|\n"
	fi
	printf "${dashes}\n\n"
	return
}

#-------------------------------------#
# Added by Martinski W. [2026-May-31] #
#-------------------------------------#
_DownloadFileFromRepo_()
{
	if [ $# -lt 2 ]
	then
		echo "**ERROR**: NO Parameters"
		return 1
	fi
	local theSRCE="$1"  theDEST="$2"

	curl --silent --fail --retry 3 --retry-delay 3 --retry-all-errors --connect-timeout 15 --max-time 30 "$theSRCE" -o "$theDEST"
	return $?
}

#----------------------------------------#
# Modified by Martinski W. [2026-May-31] #
#----------------------------------------#
UpdateScript()
{
	clear
	banner

	if [ -f "$df" ]
	then
		echo "On develop branch."
		giturl="$giturld"
	fi
	rm "$vf" 2>/dev/null

	_DownloadFileFromRepo_ "${giturl}/version.txt" "$vf"
	if [ -s "$vf" ]
	then
		nv="$(cat "$vf" | head -n 1)"
		echo "Latest version: $nv"
		echo "Current version: $REV"
		if PromptYN "Proceed with update? (y/n):"
		then
			echo -e "\nDownloading..."
			_DownloadFileFromRepo_ "${giturl}/knock.sh" "$sf"
			chmod 755 "$sf"
			echo "Installing..."
			$sf -install -force
			echo "Restarting..."
			$sf -start -nobanner
			echo "Update completed."
			echo
			echo -e "Knock version:\t$REV"
			ShowStatus
			ShowConfig quietCheck
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

#----------------------------------------#
# Modified by Martinski W. [2026-May-31] #
#----------------------------------------#
EditPortKnockConfig()
{
	# Temporarily add newly edited port to "fullPortLIST" #
	# If a port is found more than once, it's a DUPLICATE #
	_AddModPortsToFullList_()
	{
		local pNumber  taggedPort
		local oldPortList  modPortList  tmpPortList

		#Same previous port entries#
		[ "$1" = "$2" ] && return 0

		tmpPortList="$(echo "$1" | sed 's/,/ /g')"
		oldPortList=""
		for pNumber in $tmpPortList
		do
			taggedPort="$(_GetTaggedPortNumber_ "$pNumber")"
			oldPortList="${oldPortList:+$oldPortList }$taggedPort"
		done

		tmpPortList="$(echo "$2" | sed 's/,/ /g')"
		modPortList=""
		for pNumber in $tmpPortList
		do
			taggedPort="$(_GetTaggedPortNumber_ "$pNumber")"
			modPortList="${modPortList:+$modPortList }$taggedPort"
		done

		#Same tagged port entries#
		[ "$oldPortList" = "$modPortList" ] && return 0

		for pNumber in $modPortList
		do
			if echo "$oldPortList" | grep -qw "\b${pNumber}\b"
			then continue
			fi
			fullPortLIST="${fullPortLIST:+$fullPortLIST }$pNumber"
		done
	}

	EditPortKnockEntry()
	{
		local portCount  errorFound=false
		local pNumber  pIFace  allGood  portCount

		#Edit comment#
		st="$comment"
		header="     Comment:"
		editline
		comment="$st"

		#Edit ports#
		st="$ports"
		header="     Port(s):"
		editline
		st="$(_NormalizeCSVList_ "$st")"
		allGood=true
		portCount=0
		modPorts="$(echo "$st" | sed 's/,/ /g')"
		_AddModPortsToFullList_ "$ports" "$modPorts"

		for pNumber in $modPorts
		do
			portCount="$((portCount + 1))"
			if ! _ValidatePortNumber_ "$pNumber" NOLOG
			then allGood=false
			fi
			if _CheckDupPortFound_ "$pNumber" NOLOG
			then allGood=false
			fi
		done
		if [ "$portCount" -gt 2 ]
		then
			allGood=false
			_LogMsg_ "**ERROR**: INVALID number of ports [$st] found" "$pLogERROR" NOLOG
		fi
		if "$allGood"
		then
			ports="$st"
		else
			errorFound=true
			printf "Port list [$st] is ${ERRORct}INVALID${CLEARct}. Changes not saved.\n\n"
		fi

		#Edit interfaces#
		st="$interfaces"
		header="Interface(s):"
		editline
		st="$(_NormalizeCSVList_ "$st")"
		allGood=true
		for pIFace in $(echo "$st" | sed 's/,/ /g')
		do
			if _CheckInterface_ "$pIFace" NOLOG
			then continue
			fi
			allGood=false  #INACTIVE IFace#
		done
		if "$allGood"
		then
			interfaces="$st"  #ACTIVE IFace(s)#
		else
			errorFound=true
			printf "Interface list [$st] is ${ERRORct}INVALID${CLEARct}. Changes not saved.\n\n"
		fi

		#Edit command#
		st="$cmd"
		header="     Command:"
		editline
		cmd="$st"
		"$errorFound" && return 1 || return 0
	}

	#Read configuration file into virtual array#
	commandNum=0
	cfgUpdated=false
	lastComment=""
	selectEdit=""
	#Check Duplicate Ports#
	fullPortLIST="" ; dupPortLIST=""
	tempPKnockRules="/tmp/var/${scriptFNameTag}_Rules.TMP"

	while read -r thePORTS theIFACE theCMDx
	do
		if [ -z "$thePORTS" ]
		then
			lastComment=""
			continue
		fi
		if [ "$(echo "$thePORTS" | cut -c 1-1)" != "#" ]
		then
			#Load data into pseudo array#
			commandNum="$((commandNum + 1))"
			if [ -z "$lastComment" ]
			then
				eval comment$commandNum=""
			else
				eval comment$commandNum=\"$lastComment\"
				lastComment=""
			fi
			eval ports$commandNum=\"${thePORTS}\"
			eval interfaces$commandNum=\"${theIFACE}\"
			eval cmd$commandNum=\"${theCMDx}\"
		else
			lastComment="$(echo "$thePORTS $theIFACE $theCMDx" | cut -c 2- | sed 's/^ *//')"
		fi
	done < "$cf"
	commandCount="$commandNum"

	#Edit menu loop#
	while true
	do
		clear
		cols="$(stty size | awk '{print $2}')"  #Console width#
		dashes="$(head -c "$cols" </dev/zero | tr '\0' '-')"
		printf "\nPlease wait...\n"
		_CheckConfigurationFile_ silent

		{
			printf "\nThe following ports/interfaces will execute these router commands:\n"
			commandNum=0

			#Display virtual array#
			while [ "$commandNum" -lt "$commandCount" ]
			do
				commandNum="$((commandNum + 1))"
				comment="$(eval echo \"\$comment$commandNum\")"
				kPorts="$(eval echo \"\$ports$commandNum\")"
				IFaces="$(eval echo \"\$interfaces$commandNum\")"
				theCMD="$(eval echo \"\$cmd$commandNum\")"

				echo "$dashes"
				printf "Command ${GREENct}#%d${CLEARct}\n" "$commandNum"
				printf "-----------\n"
				printf "\t%s\n" "$comment"
				printf "\tPort(s): %s on %s\n" "$kPorts" "$IFaces"
				printf "\tCommand: %s\n" "$theCMD"

				kPorts="$(_NormalizeCSVList_ "$kPorts")"
				IFaces="$(_NormalizeCSVList_ "$IFaces")"
				portIFacesLst="$(echo "$IFaces" | tr ',' ' ')"
				portNumSeqLst="$(echo "$kPorts" | tr ',' ' ')"
				portListCount="$(echo "$kPorts" | awk -F',' '{print NF}')"
				activeIFaceOK=true ; portNumOK=true

				for pIFace in $portIFacesLst
				do
					if ! _CheckInterface_ "$pIFace" NOLOG
					then activeIFaceOK=false
					fi
				done

				for pNumber in $portNumSeqLst
				do
					if ! _ValidatePortNumber_ "$pNumber" NOLOG
					then portNumOK=false
					fi
					if _CheckDupPortFound_ "$pNumber" NOLOG
					then portNumOK=false
					fi
				done

				if [ "$portListCount" -gt 2 ]
				then
					portNumOK=false
					_LogMsg_ "**ERROR**: INVALID number of ports [$kPorts] found" "$pLogERROR" NOLOG
				fi

				if [ "$portNumOK" = "false" ] || \
				   [ "$activeIFaceOK" = "false" ]
				then
					_LogMsg_ "**ERROR**: The port knock entry is INVALID" "$pLogERROR" NOLOG
					echo
					continue
				fi

				#Display URLs#
				portN1="$(echo "$kPorts" | awk -F',' '{print $1}')"
				pIFace="$(echo "$IFaces" | awk -F',' '{print $1}')"
				IFaceIPaddr="$(_Get_IFace_IPAddress_ "$pIFace")"

				if [ "$portListCount" -eq 1 ]
				then printf "\tURL to send port knock: "
				else printf "\tURL to initiate port knock sequence: "
				fi
				printf "http://%s:%s\n" "$IFaceIPaddr" "$portN1"

				if [ "$portListCount" -gt 1 ]
				then
					portN2="$(echo "$kPorts" | awk -F',' '{print $2}')"
					printf "\t\tWait $((INTERVAL * 3)) seconds to complete sequence and send command: " 
					printf "http://%s:%s\n" "$IFaceIPaddr" "$portN2"
				fi
				echo
			done
			echo "$dashes"
		} > "$tempPKnockRules"

		#Using "more" command for long config files#
		more "$tempPKnockRules"

		while true
		do
			printf "[${GREENct}E${CLEARct}]dit command, "
			printf "[${GREENct}A${CLEARct}]dd command, "
			printf "[${GREENct}D${CLEARct}]elete command, "
			printf "[${GREENct}Q${CLEARct}]uit? "
			printf "[${GREENct}e,a,d,q${CLEARct}]: "
			read -r selectEdit
			if echo "$selectEdit" | grep -qE '^[Qq]$'
			then break
			elif echo "$selectEdit" | grep -qE '^[AaDdEe]$'
			then echo ; break
			fi
		done

		case "$selectEdit" in
		 [Aa])
			#Add New Command#
			commandNum="$commandCount"
			comment="Example comment"
			ports=44444
			interfaces="br0"
			cmd="ls #example command"
			if [ "$commandNum" -gt 0 ]
			then
				ports="$(eval echo \"\$ports$commandNum\")"
				ports="$((ports + 1))"
				comment="$(eval echo \"\$comment$commandNum\")"
				interfaces="$(eval echo \"\$interfaces$commandNum\")"
				cmd="$(eval echo \"\$cmd$commandNum\")"
			fi
			commandNum="$((commandNum + 1))"
			commandCount="$commandNum"

			printf "Adding new Command ${GREENct}#%d${CLEARct}\n" "$commandNum"
			printf "----------------------\n"
			if EditPortKnockEntry
			then
				printf "\nSave changes to port knock entry? (${GREENct}y${CLEARct}=Yes, ${GREENct}n${CLEARct}=No):"
				if PromptYN
				then
					eval comment$commandNum=\"$comment\"
					eval ports$commandNum=\"$ports\"
					eval interfaces$commandNum=\"$interfaces\"
					eval cmd$commandNum=\"$cmd\"
					cfgUpdated=true
				else
					commandCount="$((commandCount - 1))"
				fi
			else
				commandCount="$((commandCount - 1))"
				printf "\nPort knock entry cannot be saved.\n"
				_PressAnyKey_
			fi
			;;

		 [Dd])
			#Delete Command#
			exitDelete=false
			while true
			do
				printf "Enter command number to delete [${GREENct}1-${commandCount}${CLEARct}, ${GREENct}e${CLEARct}=Exit]: "
				read -r commandNum
				if echo "$commandNum" | grep -qE '^(E|e|exit)$'
				then
					exitDelete=true
					break
				elif [ -n "$commandNum" ] && \
				     echo "$commandNum" | grep -qE "^[1-9][0-9]?$" && \
				     [ "$commandNum" -gt 0 ] && [ "$commandNum" -le "$commandCount" ]
				then
					break
				fi
			done

			if [ "$exitDelete" = "false" ]
			then
				printf "\nDelete knock entry ${REDct}#${commandNum}${CLEARct}? (${GREENct}y${CLEARct}=Yes, ${GREENct}n${CLEARct}=No):"
				if PromptYN
				then
					while [ "$commandNum" -lt "$commandCount" ]
					do
						commandnumold="$((commandNum + 1))"
						comment="$(eval echo \"\$comment$commandnumold\")"
						ports="$(eval echo \"\$ports$commandnumold\")"
						interfaces="$(eval echo \"\$interfaces$commandnumold\")"
						cmd="$(eval echo \"\$cmd$commandnumold\")"
						eval comment$commandNum=\"$comment\"
						eval ports$commandNum=\"$ports\"
						eval interfaces$commandNum=\"$interfaces\"
						eval cmd$commandNum=\"$cmd\"
						commandNum="$commandnumold"
					done
					commandCount="$((commandCount - 1))"
					cfgUpdated=true
				fi
			fi
			;;

		 [Ee])
			#Edit Existing Command#
			exitEdit=false
			while true
			do
				printf "Enter command number to edit [${GREENct}1-${commandCount}${CLEARct}, ${GREENct}e${CLEARct}=Exit]: "
				read -r commandNum
				if echo "$commandNum" | grep -qE '^(E|e|exit)$'
				then
					exitEdit=true
					break
				elif [ -n "$commandNum" ] && \
				     echo "$commandNum" | grep -qE "^[1-9][0-9]?$" && \
				     [ "$commandNum" -gt 0 ] && [ "$commandNum" -le "$commandCount" ]
				then
					break
				fi
			done

			if [ "$exitEdit" = "false" ]
			then
				comment="$(eval echo \"\$comment$commandNum\")"
				ports="$(eval echo \"\$ports$commandNum\")"
				interfaces="$(eval echo \"\$interfaces$commandNum\")"
				cmd="$(eval echo \"\$cmd$commandNum\")"
				clear
				printf "Editing Command ${GREENct}#%d${CLEARct}\n" "$commandNum"
				printf "-------------------\n"
				printf "\t%s\n" "$comment"
				printf "\tPort(s): %s on %s\n" "$ports" "$interfaces"
				printf "\tCommand: %s\n" "$cmd"
				printf "${dashes}\n"
				if EditPortKnockEntry
				then
					printf "\nSave changes to port knock entry? (${GREENct}y${CLEARct}=Yes, ${GREENct}n${CLEARct}=No):"
					if PromptYN
					then
						eval comment$commandNum=\"$comment\"
						eval ports$commandNum=\"$ports\"
						eval interfaces$commandNum=\"$interfaces\"
						eval cmd$commandNum=\"$cmd\"
						cfgUpdated=true
					fi
				else
					printf "\nPort knock entry cannot be saved.\n"
					_PressAnyKey_
				fi
			fi
			;;

		 [Qq]) break;;
		esac
	done

	echo
	rm -f "$tempPKnockRules"

	if "$cfgUpdated"
	then
		printf "Save changes to config file? (${GREENct}y${CLEARct}=Yes, ${GREENct}n${CLEARct}=No):"
		if PromptYN
		then
			echo -en "\nSaving configuration"
			echo "#knock.sh configuration file" > "$cf"
			echo -e "\n#Format Port Number <space> Interface(s) [comma separated] <space> Command to execute [to end of line]\n" >> "$cf"

			#Write virtual array back to config file#
			commandNum=0
			while [ "$commandNum" -lt "$commandCount" ]
			do
				commandNum="$((commandNum + 1))"
				echo -n "..."$commandNum
				echo "$(eval echo \"#\$comment$commandNum\")" >> "$cf"
				echo $(eval echo \"\$ports$commandNum \$interfaces$commandNum \$cmd$commandNum\") >> "$cf"
				echo >> "$cf"
			done
			echo -e "\n\nNew config file:"
			echo "$dashes"
			more "$cf"
			echo "$dashes"
			_PressAnyKey_
		else
			echo
			cfgUpdated=false
		fi
	fi

	if [ $# -lt 2 ] || [ -z "$2" ]
	then
		clear
		banner
		echo "Thanks for using knock.sh!"
	fi
	return 0
}

#-------------------------------------#
# Added by Martinski W. [2026-May-31] #
#-------------------------------------#
_CheckForDuplicatePorts_()
{
    local taggedPort  dupPortFound=false
    local tmpPortLIST  pNumber  foundCount  tagPortLIST

    dupPortLIST="" ; tagPortLIST=""

    for pNumber in $fullPortLIST
    do
        taggedPort="$(_GetTaggedPortNumber_ "$pNumber")"
        tagPortLIST="${tagPortLIST:+$tagPortLIST }$taggedPort"
    done
    fullPortLIST="$tagPortLIST"

    tmpPortLIST="$(echo "$fullPortLIST" | awk -v RS=' ' '{print}')"

    for pNumber in $fullPortLIST
    do
        foundCount="$(echo "$tmpPortLIST" | grep -cw "\b${pNumber}\b")"
        if [ "$foundCount" -gt 1 ]
        then
            dupPortFound=true
            tmpPortLIST="$(echo "$tmpPortLIST" | grep -vw "\b${pNumber}\b")"
            dupPortLIST="${dupPortLIST:+$dupPortLIST }$pNumber"
            "$isVerboseMode" && \
            _LogMsg_ "**ERROR**: Duplicate port [${pNumber//_/:}] found in the configuration file" "$pLogERROR"
        fi
    done

    "$dupPortFound" && return 0 || return 1
}

#-------------------------------------#
# Added by Martinski W. [2026-May-31] #
#-------------------------------------#
_CheckDupPortFound_()
{
    if [ $# -eq 0 ] || [ -z "$1" ]
    then return 0
    fi
    local tmpPortList=""  logARG=""
    local taggedPort  findCount  dupPortFound=false

    if [ $# -gt 1 ] && [ -n "$2" ] && \
       echo "$2" | grep -qE '^(NOLOG|silent)$'
    then logARG="$2"
    fi

    taggedPort="$(_GetTaggedPortNumber_ "$1")"
    if [ "${#dupPortLIST}" -gt 0 ] && \
       echo "$dupPortLIST" | grep -qw "\b${taggedPort}\b"
    then
        [ "$logARG" != "silent" ] && \
        _LogMsg_ "**ERROR**: Duplicate port [$1] was found" "$pLogERROR" "$logARG"
        return 0
    fi

    [ "${#fullPortLIST}" -eq 0 ] && return 0
    tmpPortList="$(echo "$fullPortLIST" | awk -v RS=' ' '{print}')"
    findCount="$(echo "$tmpPortList" | grep -cw "\b${taggedPort}\b")"
    if [ "$findCount" -gt 1 ]
    then
        [ "$logARG" != "silent" ] && \
        _LogMsg_ "**ERROR**: Duplicate port [$1] was found" "$pLogERROR" "$logARG"
        return 0
    fi
    return 1
}

#-------------------------------------#
# Added by Martinski W. [2026-May-31] #
#-------------------------------------#
_CheckConfigurationFile_()
{
    if [ ! -s "$cf" ]
    then
	    _LogMsg_ "**ERROR**: Missing configuration file [$cf]" "$pLogERROR"
	    return 1
    fi
    local cfgLINE  thePORTx  theIFACE  theCMDx
    local portNumOK  activeIFaceOK  errorFound=false
    local portIFacesLst  portNumSeqLst  portListCount
    local isVerboseMode=true  silentARG=""

    if [ $# -gt 0 ] && [ "$1" = "silent" ]
    then
        silentARG="$1" ; isVerboseMode=false
    fi

    #To Check for Duplicate Ports#
    fullPortLIST=""  dupPortLIST=""

    while read -r cfgLINE
    do
        if [ -z "$cfgLINE" ] || \
           echo "$cfgLINE" | grep -qE "^[[:blank:]]*[#].*"
        then continue  #SKIP#
        fi
        cfgLINE="$(echo "$cfgLINE" | sed 's/  \+/  /')"
        thePORTx="$(echo "$cfgLINE" | awk -F' ' '{print $1}')"
        theIFACE="$(echo "$cfgLINE" | awk -F' ' '{print $2}')"
        theCMDx="$(echo "$cfgLINE" | awk -F' ' '{match($0, $3); print substr($0, RSTART)}')"

        if [ -z "$thePORTx" ] || [ -z "$theIFACE" ] || [ -z "$theCMDx" ]
        then
            errorFound=true
            "$isVerboseMode" && \
            _LogMsg_ "**ERROR**: The port knock entry [$cfgLINE] is INVALID" "$pLogERROR"
            continue
        fi

        thePORTx="$(_NormalizeCSVList_ "$thePORTx")"
        theIFACE="$(_NormalizeCSVList_ "$theIFACE")"
        portIFacesLst="$(echo "$theIFACE" | tr ',' ' ')"
        portNumSeqLst="$(echo "$thePORTx" | tr ',' ' ')"
        portListCount="$(echo "$thePORTx" | awk -F',' '{print NF}')"
        fullPortLIST="${fullPortLIST:+$fullPortLIST }$portNumSeqLst"
        activeIFaceOK=true ; portNumOK=true

        for pIFace in $portIFacesLst
        do
            if ! _CheckInterface_ "$pIFace" "$silentARG"
            then activeIFaceOK=false
            fi
        done
        for pNumber in $portNumSeqLst
        do
            if ! _ValidatePortNumber_ "$pNumber" "$silentARG"
            then portNumOK=false
            fi
        done

        if [ "$portListCount" -gt 2 ]
        then
            portNumOK=false
            "$isVerboseMode" && \
            _LogMsg_ "**ERROR**: INVALID number of ports [$thePORTx] found" "$pLogERROR"
        fi

        if [ "$portNumOK" = "false" ] || \
           [ "$activeIFaceOK" = "false" ]
        then
            errorFound=true
            "$isVerboseMode" && \
            _LogMsg_ "**ERROR**: The port knock entry [$cfgLINE] is INVALID" "$pLogERROR"
            "$isVerboseMode" && echo
        fi
    done < "$cf"

    if _CheckForDuplicatePorts_
    then errorFound=true
    fi

    if "$errorFound"
    then
        "$isVerboseMode" && \
        _LogMsg_ "**ERROR**: Configuration file [$cf] contains some errors" "$pLogERROR"
        "$isVerboseMode" && echo
    fi

    return 0
}

##-------------------------------------##
## Added by Martinski W. [2026-May-17] ##
##-------------------------------------##
readonly knockMutexFLock_FD=564
readonly knockMutexFLock_FN="/tmp/var/${scriptFNameTag}_Loop.FLOCK"
knockMutexFLock_OK=false  #DO NOT have FLock#

_ReleaseMutexFLock_()
{
    if [ $# -gt 0 ] && \
       [ "$1" = "checkLockOK" ] && \
       [ "$knockMutexFLock_OK" = "false" ]
    then return 0
    fi
    printf '' > "$knockMutexFLock_FN"
    flock -u "$knockMutexFLock_FD" 2>/dev/null
    knockMutexFLock_OK=false
}

_AcquireMutexFLock_()
{
    local retCode  procInfo  procName  procIDno  procIDof=""

    if [ -s "$knockMutexFLock_FN" ]
    then
        procInfo="$(head -n1 "$knockMutexFLock_FN")"
        procName="$(echo "$procInfo" | cut -d'|' -f1)"
        procIDno="$(echo "$procInfo" | cut -d'|' -f2)"
        if [ -n "$procName" ] && [ -n "$procIDno" ]
        then procIDof="$(pidof "$procName")"
        fi
        if [ -z "$procIDof" ] || \
           ! echo "$procIDof" | grep -qow "$procIDno"
        then
            _LogMsg_ "Stale Lock Found. Resetting Lock file..." "$pLogWARNG"
            _ReleaseMutexFLock_
        fi
    fi

    [ ! -s "$knockMutexFLock_FN" ] && \
    eval exec "$knockMutexFLock_FD>$knockMutexFLock_FN"

    if flock -x -n "$knockMutexFLock_FD" 2>/dev/null
    then
        printf "$(basename "$0")|$$\n" > "$knockMutexFLock_FN"
        retCode=0 ; knockMutexFLock_OK=true
    else
        procInfo="$(head -n1 "$knockMutexFLock_FN")"
        if [ -n "$procInfo" ]
        then procInfo="$(echo "$procInfo" | sed 's/|/, PID=/')"
        fi
        _LogMsg_ "**ERROR**: Another process [$procInfo] has the Lock." "$pLogERROR"
        retCode=1 ; knockMutexFLock_OK=false
    fi

    return "$retCode"
}

#----------------------------------------#
# Modified by Martinski W. [2026-May-31] #
#----------------------------------------#
ShowConfig()
{
	local lastComment  commandNum=0  portNx  IFaceIPaddr
	local portIFacesLst  portNumSeqLst  portListCount
	local activeIFaceOK  portNumOK  pIFace  pNumber
	local fullPortLIST=""  dupPortLIST=""  silentARG=""

	if [ $# -gt 0 ] && [ "$1" = "quietCheck" ]
	then silentARG="silent"
	fi

	if ! _CheckConfigurationFile_ "$silentARG"
	then return 1
	fi

	lastComment=""
	printf "The following ports/interfaces will execute these router commands:\n\n"

	while read -r thePORTS theIFACE theCMDx
	do
		if [ -z "$thePORTS" ]
		then
			lastComment=""
			continue
		fi
		if [ "$(echo "$thePORTS" | cut -c 1-1)" != "#" ]
		then
			commandNum="$((commandNum + 1))"
			printf "Command ${GREENct}#%d${CLEARct}\n" "$commandNum"
			printf "-----------\n"
			if [ -n "$lastComment" ]
			then
				printf "\t%s\n" "$lastComment"
				lastComment=""
			fi
			printf "\tPort(s): %s on %s\n" "$thePORTS" "$theIFACE"
			printf "\tCommand: %s\n" "$theCMDx"

			thePORTS="$(_NormalizeCSVList_ "$thePORTS")"
			theIFACE="$(_NormalizeCSVList_ "$theIFACE")"
			portIFacesLst="$(echo "$theIFACE" | tr ',' ' ')"
			portNumSeqLst="$(echo "$thePORTS" | tr ',' ' ')"
			portListCount="$(echo "$thePORTS" | awk -F',' '{print NF}')"
			activeIFaceOK=true ; portNumOK=true

			for pIFace in $portIFacesLst
			do
				if ! _CheckInterface_ "$pIFace" NOLOG
				then activeIFaceOK=false
				fi
			done

			for pNumber in $portNumSeqLst
			do
				if ! _ValidatePortNumber_ "$pNumber" NOLOG
				then portNumOK=false
				fi
				if _CheckDupPortFound_ "$pNumber" NOLOG
				then portNumOK=false
				fi
			done

			if [ "$portListCount" -gt 2 ]
			then
				portNumOK=false
				_LogMsg_ "**ERROR**: INVALID number of ports [$thePORTS] found" "$pLogERROR" NOLOG
			fi

			if [ "$portNumOK" = "false" ] || \
			   [ "$activeIFaceOK" = "false" ]
			then
				_LogMsg_ "*WARNING*: The port knock entry may be ignored" "$pLogWARNG" NOLOG
				echo
				continue
			fi

			#Display URLs#
			portN1="$(echo "$thePORTS" | awk -F',' '{print $1}')"
			pIFace="$(echo "$theIFACE" | awk -F',' '{print $1}')"
			IFaceIPaddr="$(_Get_IFace_IPAddress_ "$pIFace")"

			if [ "$portListCount" -eq 1 ]
			then printf "\tURL to send port knock: "
			else printf "\tURL to initiate port knock sequence: "
			fi
			printf "http://%s:%s\n" "$IFaceIPaddr" "$portN1"

			if [ "$portListCount" -gt 1 ]
			then
				portN2="$(echo "$thePORTS" | awk -F',' '{print $2}')"
				printf "\t\tWait $((INTERVAL * 3)) seconds to complete sequence and send command: "
				printf "http://%s:%s\n" "$IFaceIPaddr" "$portN2"
			fi
			echo
		else
			lastComment="$(echo "$thePORTS $theIFACE $theCMDx" | cut -c 2- | sed 's/^ *//')"
		fi
	done < "$cf"
}

#-------------------------------------#
# Added by Martinski W. [2026-May-31] #
#-------------------------------------#
_MenuShowConfig_()
{
	clear ; banner
	ShowConfig quietCheck
	return 0
}

#-------------------------------------#
# Added by Martinski W. [2026-May-31] #
#-------------------------------------#
_WaitForCustomFirewallRules_()
{
    local sleepSecsNUM=0  sleepSecsMAX

    if [ $# -eq 0 ] || [ -z "$1" ] || \
       ! echo "$1" | grep -qE "^[1-9][0-9]?$"
    then sleepSecsMAX=10
    else sleepSecsMAX="$1"
    fi

    while [ "$((sleepSecsNUM++))" -lt "$sleepSecsMAX" ]
    do
        sleep 1
        if iptables -S INPUT | grep -q '\bknock.sh'
        then break
        fi
    done
}

#-------------------------------------#
# Added by Martinski W. [2026-Jun-02] #
#-------------------------------------#
_WaitForBackgroundScreenProcess_()
{
    local sleepSecsNUM=0  sleepSecsMAX

    if [ $# -eq 0 ] || [ -z "$1" ] || \
       ! echo "$1" | grep -qE "^[1-9][0-9]?$"
    then sleepSecsMAX=10
    else sleepSecsMAX="$1"
    fi

    while [ "$((sleepSecsNUM++))" -lt "$sleepSecsMAX" ]
    do
        sleep 1
        if /opt/sbin/screen -ls knock >/dev/null
        then break
        fi
    done
}

#-------------------------------------#
# Added by Martinski W. [2026-May-31] #
#-------------------------------------#
_StartBackgroundProcess_()
{
	if ! _CheckConfigurationFile_
	then return 1
	fi

	service restart_firewall >/dev/null
    sleep 1

	if [ -x /opt/sbin/screen ] && \
	   /opt/sbin/screen -ls knock >/dev/null
	then  #Make sure ONLY ONE background process is run#
		printf "An existing background process must be stopped first. Please wait...\n"
		/opt/sbin/screen -S knock -X quit >/dev/null
		sleep 3  #Allow time to terminate process#
	fi

	printf "Waiting to set firewall rules. Please wait...\n"
	_WaitForCustomFirewallRules_ 5
	printf "Starting knock.sh background process. Please wait...\n"

	if $sf "-screen"
	then
		if [ $# -eq 0 ] || [ -z "$1" ]
		then
			clear
			banner
			printf "\nKnock.sh has started and is ready for port knocks\n\n"
			ShowConfig quietCheck
		else
			printf "Knock.sh has started and is ready for port knocks\n"
		fi
	else
		printf "\nERROR: Cannot start knock process in background\n\n"
		return 1
	fi
	return 0
}

#-------------------------------------#
# Added by Martinski W. [2026-May-31] #
#-------------------------------------#
_StopBackgroundProcess_()
{
	if [ $# -eq 0 ] || [ -z "$1" ]
	then
		clear ; banner
	fi
	printf "\nStopping knock.sh background process. Please wait...\n"
	/opt/sbin/screen -S knock -X quit >/dev/null
	sleep 3  #Allow time to terminate process#
	printf "Knock.sh background process stopped\n"
	return 0
}

#-------------------------------------#
# Added by Martinski W. [2026-May-31] #
#-------------------------------------#
_InvalidMenuOptionHandler_()
{
	if [ -n "$menuSelection" ]
	then printf "\n Invalid menu option [$menuSelection]\n"
	fi
	printf "\n Select a valid menu option\n"
	_PressAnyKey_
}

#----------------------------------------#
# Modified by Martinski W. [2026-May-24] #
#----------------------------------------#
## Main Menu ##
if [ $# -eq 0 ] || [ -z "$1" ]
then
	menuSelection="" ; cfgUpdated=false

	while true
	do
		clear
		banner
		ShowStatus

		printf " Main Menu\n"
		printf " =========\n\n"
		printf " ${GREENct}1${CLEARct}. Install/reinstall knock.sh\n"
		printf " ${GREENct}2${CLEARct}. Uninstall knock.sh\n"
		if CheckInstall
		then
			printf " ${GREENct}3${CLEARct}. Display knock.sh config file\n"
			printf " ${GREENct}4${CLEARct}. Start/restart knock.sh background process\n"
			printf " ${GREENct}5${CLEARct}. Stop knock.sh background process\n"
			printf " ${GREENct}6${CLEARct}. Edit knock.sh config file\n"
			printf " ${GREENct}7${CLEARct}. Update script to latest version\n"
		fi
		printf "\n ${GREENct}e${CLEARct}. Exit\n\n"
		printf " Enter selection: "
		read -r menuSelection

		case "$menuSelection" in
			1)
				$sf -install -force
				_StopBackgroundProcess_ -nobanner >/dev/null

			if CheckInstall
			then
				if [ -f "$tf" ]
				then
					echo -ne "\t"
					if PromptYN "Restore saved config file ($tf)? (y/n):"
					then
						echo -en "\n\tRestoring saved file..."
						cp $tf $cf
						echo -e $cm
					else
						echo -e "\n\tKeeping default file."
					fi
				fi
				printf "\nKnock.sh version $REV successfully installed!\n\n"

				if PromptYN "Would you like to edit the config file now ($cf)? (y/n):"
				then
					echo
					$sf -edit -nobanner
					if PromptYN "Are you ready to start processing knocks (start knock.sh)? (y/n):"
					then
						echo
						$sf -start -nobanner
					else
						printf "\nWhen ready, please run start from main menu\n"
					fi
				else
					printf "\nPlease edit the configuration file from main menu\n\n"
					printf "Once updated, please run choose start from the main menu to begin processing port knocks\n"
				fi
			fi
				_PressAnyKey_
				exec "$sf"
				exit
				;;
			2)
				sh "$sf" -uninstall
				exit
				;;
			[Ee]) break;;
		esac

		if ! CheckInstall
		then
			_InvalidMenuOptionHandler_
			continue
		fi

		case "$menuSelection" in
			3)
				_MenuShowConfig_
				_PressAnyKey_
				;;
			4)
				_StartBackgroundProcess_ -nobanner
				_PressAnyKey_
				;;
			5)
				_StopBackgroundProcess_ -nobanner
				_PressAnyKey_
				;;
			6)
				EditPortKnockConfig -edit -nobanner
				if "$cfgUpdated"
				then
					if PromptYN "Are you ready to start processing knocks (start knock.sh)? (y/n):"
					then
						echo
						_StartBackgroundProcess_ -nobanner
					else
						echo
						_StopBackgroundProcess_ -nobanner
					fi
				fi
				_PressAnyKey_
				;;
			7)
				if UpdateScript
				then
					_PressAnyKey_ "Press ANY key to restart knock.sh..."
					clear
					exec $sf
					exit
				else
					_PressAnyKey_
				fi
				;;
			*) _InvalidMenuOptionHandler_
				;;
		esac
	done

	clear
	banner
	printf "\nThanks for using knock.sh!\n\n"
	exit
fi

if [ "$1" = "-status" ]
then
    clear
    banner
    ShowStatus
    exit
fi

if [ "$1" = "-config" ]
then
	_MenuShowConfig_
	exit 0
fi

#----------------------------------------#
# Modified by Martinski W. [2026-Jun-02] #
#----------------------------------------#
if [ "$1" = "-screen" ]
then
	if [ ! -x /opt/sbin/screen ]
	then
		_LogMsg_ "**ERROR**: Entware Screen app not installed" "$pLogERROR"
		exit 1
	fi
	if [ ! -s "$sf" ]
	then
		_LogMsg_ "**ERROR**: knock.sh is not installed yet" "$pLogERROR"
		exit 1
	fi

	_LogMsg_ "Starting knock.sh background process" "$pLogWARNG" NOECHO

	if /opt/sbin/screen -ls knock >/dev/null
	then  #Stop the old process first#
		/opt/sbin/screen -S knock -X quit >/dev/null
		sleep 3  #Allow time to terminate process#
	fi

	#Kill rogue background process#
	roguePID="$(ps w | grep -E '/[k]nock.sh -loop')"
	if [ -n "$roguePID" ]
	then
		roguePID="$(echo "$roguePID" | awk -F' ' '{print $1}')"
		kill -TERM "$roguePID" >/dev/null 2>&1
		_LogMsg_ "Force killed knock.sh process [$roguePID] during restart" "$pLogWARNG"
		sleep 2  #Allow time to terminate process#
	fi

	/opt/sbin/screen -dmS knock "$sf" -loop
	printf "Waiting for background process. Please wait...\n"

	_WaitForCustomFirewallRules_ 5
	_WaitForBackgroundScreenProcess_ 5
	CheckStatus && exit 0 || exit 1
fi

#----------------------------------------#
# Modified by Martinski W. [2026-May-31] #
#----------------------------------------#
if [ "$1" = "-firewall" ]
then
	fullPortLIST="" ; dupPortLIST=""

	if ! _CheckConfigurationFile_
	then exit 1
	fi
	_LogMsg_ "Adding port knocking rules to firewall" "$pLogWARNG"
	echo

	while read -r cfgLINE
	do
		if [ -z "$cfgLINE" ] || \
		   echo "$cfgLINE" | grep -qE "^[[:blank:]]*[#].*"
		then continue  #SKIP#
		fi
		cfgLINE="$(echo "$cfgLINE" | sed 's/  \+/  /')"
		thePORTS="$(echo "$cfgLINE" | awk -F' ' '{print $1}')"
		theIFACE="$(echo "$cfgLINE" | awk -F' ' '{print $2}')"
		theCMDx="$(echo "$cfgLINE" | awk -F' ' '{match($0, $3); print substr($0, RSTART)}')"

		if [ -z "$thePORTS" ] || [ -z "$theIFACE" ] || [ -z "$theCMDx" ]
		then continue  #INVALID#
		fi

		thePORTS="$(_NormalizeCSVList_ "$thePORTS")"
		theIFACE="$(_NormalizeCSVList_ "$theIFACE")"
		portIFacesLst="$(echo "$theIFACE" | tr ',' ' ')"
		portNumSeqLst="$(echo "$thePORTS" | tr ',' ' ')"
		portListCount="$(echo "$thePORTS" | awk -F',' '{print NF}')"
		activeIFaceOK=true ; portNumOK=true

		for IFace in $portIFacesLst
		do
			if ! _CheckInterface_ "$IFace" silent
			then activeIFaceOK=true   #Allow FW Rule for INACTIVE IFace??#
			fi
		done

		for pNumber in $portNumSeqLst
		do
			if ! _ValidatePortNumber_ "$pNumber" silent
			then portNumOK=false
			fi
			if _CheckDupPortFound_ "$pNumber" silent
			then portNumOK=false
			fi
		done

		if [ "$portNumOK" = "false" ] || \
		   [ "$activeIFaceOK" = "false" ] || \
		   [ "$portListCount" -gt 2 ]
		then continue  #INVALID#
		fi

		for thePort in $portNumSeqLst
		do
			portN="$(echo "$thePort" | awk -F':' '{print $1}')"
			proto="$(echo "$thePort" | awk -F':' '{print $2}')"

			if [ -z "$proto" ] || [ "$proto" = "T" ]
			then proto="tcp"
			elif [ "$proto" = "U" ]
			then proto="udp"
			else proto="$(echo "$proto" | tr 'UDTCP' 'udtcp')"
			fi

			for IFace in $portIFacesLst
			do
				iptables -D INPUT -i "$IFace" -p "$proto" -m "$proto" --dport "$portN" -j LOG --log-prefix "knock.sh " --log-level info 2>/dev/null
				iptables -I INPUT -i "$IFace" -p "$proto" -m "$proto" --dport "$portN" -j LOG --log-prefix "knock.sh " --log-level info
			done
		done
	done < "$cf"

	exit 0
fi

if [ "$1" = "-install" ]
then
	if [ $# -lt 2 ] || [ -z "$2" ]
	then
		clear
		banner
		if ! PromptYN "Proceed with installing knock? (y/n):"
		then
			printf "\nThanks for trying knock.sh!\n"
			exit 0
		fi
		printf "\nInstalling knock.sh...\n"
	fi

	#Check run location#
	if [ "$(dirname "$fn")" != "$js" ]
	then
		echo "Error: This script must be run from $js"
		exit 1
	fi
	chmod 755 "$sf"

	#Check entware
	echo -ne "\tChecking for Entware..."
	if [ ! -f "/opt/bin/opkg" ]; then
		echo -e "\nError: Knock.sh requires Entware. Please install Entware using the 'amtm' utility."
		exit 1
	fi
	echo -e $cm

	#Check screen, optionally install
	echo -ne "\tChecking for Screen utility..."
	if [ ! -f "/opt/sbin/screen" ]
	then
		printf "\n\nKnock.sh requires the Entware utility 'screen'\n"

		if PromptYN "Proceed with installing 'screen'? (y/n):"
		then
			echo
			opkg install screen
			if [ ! -f "/opt/sbin/screen" ]; then
				echo "Entware screen install failed"
				exit 1
			fi
		else
			echo
			echo "Cancelling install"
			exit 1
		fi
		echo -ne "\tScreen successfully installed."
	fi
	echo -e $cm

	#Setup config file#
	echo -ne "\tChecking config file..."
	if [ ! -d "${jf}/addons" ]; then
		echo -e "\nError: This script is designed for Asuswrt-Merlin firmware only"
		exit 1
	fi
	mkdir "$id" 2>/dev/null
	echo -e $cm

	if [ ! -f "$cf" ]; then
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

		if [ $# -lt 2 ] || [ -z "$2" ]
		then
		    #Optionally restore saved config file, if it exists
		 if [ -f $tf ]
		 then
			echo -ne "\t"
			if PromptYN "Restore saved config file ($tf)? (y/n):"
			then
				echo -en "\n\tRestoring saved file..."
				cp $tf $cf
				echo -e $cm
			else
				echo -e "\n\tKeeping default file."
			fi
		 fi
		fi
	fi

	#Add post-mount command#
	echo -ne "\tUpdating post-mount file..."
	if [ ! -f $pm ]; then
		echo "#!/bin/sh" > $pm
		echo >> $pm
		chmod 755 $pm
	fi
	sed -i -e '/knock.sh/d' $pm
	echo "(sleep 30 &&" $sf "-screen) & # Added by knock.sh" >> $pm
	echo -e $cm

	#Add firewall-start command#
	echo -ne "\tUpdating firewall-start file..."
	if [ ! -f "$fs" ]
	then
		echo "#!/bin/sh" > $fs
		echo >> $fs
		chmod 755 $fs
	fi
	sed -i -e '/knock.sh/d' $fs
	echo $sf "-firewall # Added by knock.sh" >> $fs
	echo -e $cm

	#add profile.add command#
	echo -ne "\tUpdating profile.add file..."
	if [ ! -f $pa ]; then
		touch $pa
	fi
	sed -i -e '/knock.sh/d' $pa
	echo "alias knock=\"sh" $sf"\" # Added by knock.sh" >> $pa
	echo -e $cm

	if [ $# -lt 2 ] || [ -z "$2" ]
	then
		printf "\nKnock.sh version $REV successfully installed!\n\n"

		if PromptYN "Would you like to edit the config file now ($cf)? (y/n):"
		then
			echo
			$sf -edit -nobanner
			if PromptYN "Are you ready to start processing knocks (start knock.sh)? (y/n):"
			then
				echo
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

#----------------------------------------#
# Modified by Martinski W. [2026-May-31] #
#----------------------------------------#
if [ "$1" = "-start" ] || [ "$1" = "-restart" ]
then
	theArg=""
	[ $# -gt 1 ] && theArg="$2"
	_StartBackgroundProcess_ "$theArg"
	exit $?
fi

#----------------------------------------#
# Modified by Martinski W. [2026-May-31] #
#----------------------------------------#
if [ "$1" = "-stop" ]
then
	theArg=""
	[ $# -gt 1 ] && theArg="$2"
	_StopBackgroundProcess_ "$theArg"
	exit $?
fi

if [ "$1" = "-uninstall" ]
then
	clear
	banner
	if ! PromptYN "Proceed with uninstalling knock? (y/n):"
	then
		printf "\n\nUninstallation was canceled. Exiting...\n"
		exit
	fi
	echo

	screen -S knock -X quit >/dev/null
	sed -i -e '/knock.sh/d' $pm	  #remove post-mount command#
	sed -i -e '/knock.sh/d' $fs	  #remove firewall-start command#
	sed -i -e '/knock.sh/d' $pa	  #remove profile.add command#

	#Remove iptable modifications#
	service restart_firewall >/dev/null

	cp $cf $tf           #Save config in temp folder#
	rm $cf               #Remove config file#
	rm $vf 2>/dev/null   #Remove version file#
	rm $df 2>/dev/null   #Remove develop flag#
	rm $sf               #Remove script file#

	#Attempt to remove installation directory#
	if [ "$(pwd)" = "$id" ]
	then
		echo "Error: cannot remove install directory $id"
	else
		rmdir "$id" 2>/dev/null
	fi

	echo
	echo "Knock.sh uninstalled"
	echo "Existing configuration file saved as $tf"
	echo "Thanks for using knock.sh!"
	exit
fi

if [ "$1" = "-develop" ]
then
	touch "$df"
	exit
fi

if [ "$1" = "-main" ]
then
	rm "$df" 2>/dev/null
	exit
fi

#----------------------------------------#
# Modified by Martinski W. [2026-May-31] #
#----------------------------------------#
if [ "$1" = "amtmupdate" ]
then
	if [ $# -gt 1 ] && [ "$2" = "check" ]
	then
		exit 0
	fi

	if [ -f "$df" ]
	then
		giturl="$giturld"
	fi
	echo -n "Running amtmupdate..."
	rm "$vf" 2>/dev/null

	_DownloadFileFromRepo_ "${giturl}/version.txt" "$vf"
	if [ -s "$vf" ]
	then
		_DownloadFileFromRepo_ "${giturl}/knock.sh" "$sf"
		chmod 755 "$sf"
		$sf -install -force >/dev/null
		$sf -start -nobanner >/dev/null
		echo -e "$cm"
		echo "amtmupdate completed."
		exit 0
	else
		echo
		echo "amtmupdate failed."
		exit 1
	fi
fi

if [ "$1" = "-update" ]
then
	UpdateScript
	exit
fi

if [ "$1" = "-edit" ]
then
	theArg=""
	[ $# -gt 1 ] && theArg="$2"
	EditPortKnockConfig "-edit" "$theArg"
	exit
fi

if [ "$1" != "-loop" ]
then
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

#----------------------------------------#
# Modified by Martinski W. [2026-May-31] #
#----------------------------------------#
Read_dmesgDATA()
{
	local IFACE  SRCIP  MSGID  DPORT  PROTO  knockMSG  tempMSG

	knockMSG="$(dmesg | grep -E '^knock.sh[[:blank:]]+' | tail -n1)"
	if [ -z "$knockMSG" ] ; then echo ; return 1 ; fi
	tempMSG="$(echo "$knockMSG" | awk -v RS=' ' '{print}')"

	IFACE="$(echo "$tempMSG" | grep '^IN=')"
	SRCIP="$(echo "$tempMSG" | grep '^SRC=')"
	MSGID="$(echo "$tempMSG" | grep '^ID=')"
	DPORT="$(echo "$tempMSG" | grep '^DPT=')"
	PROTO="$(echo "$tempMSG" | grep '^PROTO=')"

	if [ -n "${DPORT:+xSETx}" ]
	then  #Port Knock "signatures"#
		prevKnockSIG="$nextKnockSIG"
		nextKnockSIG="$DPORT $IFACE $SRCIP $PROTO"
	fi
	msgDATA="${MSGID:-ID=99999} ${DPORT:-DPT=0} $IFACE $SRCIP $PROTO"
}

#----------------------------------------#
# Modified by Martinski W. [2026-May-31] #
#----------------------------------------#
Read_dmesgID()
{
	local dmesgID
	if [ -z "$msgDATA" ] ; then echo ; return 1 ; fi
	dmesgID="$(echo "$msgDATA" | awk -F' ' '{print $1}' | awk -F '=' '{print $2}')"

	if [ "$dmesgID" -eq 0 ] && [ $# -gt 0 ] && [ "$1" = "checkID" ]
	then
		#To handle ID field from iOS always being ZERO#
		dmesgID="$FAKE_NUMID"
		echo "$FAKE_KMESG" >/dev/kmsg
		"$isDEBUG" && \
		printf "ID is ZERO. Adding fake kernel ring buffer message.\n"
	fi
	echo "$dmesgID"
}

#-----------------------------------------------#
# Make sure ONLY ONE background loop is running
#-----------------------------------------------#
if ! _AcquireMutexFLock_
then exit 1
fi

fullPortLIST="" ; dupPortLIST=""
if ! _CheckConfigurationFile_
then exit 1
fi

isDEBUG=false
portNumOK=false
thePortNum=""
srceIPaddr=""
sleepDelayMIN=3
delayINTERVAL=2
portListCount=0

knockWaitNUM=0
knockWaitMAX=60
prevKnockSIG="N/A"
nextKnockSIG="N/A"

msgDATA=""
nextID="N/A"

Read_dmesgDATA
prevID="$(Read_dmesgID checkID)"

echo "Knock.sh started"
echo "Version $REV"
_LogMsg_ "Waiting for port knocks..." "$pLogWARNG"

#----------------------------------------#
# Modified by Martinski W. [2026-May-31] #
#----------------------------------------#
while true
do
    #For Quicker Response#
    sleep "$sleepDelayMIN"
    knockWaitNUM="$((knockWaitNUM + sleepDelayMIN))"

    Read_dmesgDATA
    nextID="$(Read_dmesgID)"

    #---------------------------------------------------------#
    # Do *NOT* accept the same Port Knock within ONE minute
    # to prevent executing the same command within just secs 
    # in case a user accidentally triggers the same event.
    # But allow/accept a different Port Knock after ~8 secs.
    # This allows for faster handling of Double-Port Knocks.
    #---------------------------------------------------------#
    if { [ -z "$nextID" ] || [ "$prevID" = "$nextID" ] ; } || \
       { [ "$prevKnockSIG" = "$nextKnockSIG" ] && \
         [ "$knockWaitNUM" -lt "$knockWaitMAX" ] ; }
    then continue
    fi

    knockWaitNUM=0  #Reset for next Port Knock#
    kPORTx="$(echo "$msgDATA" | awk -F' ' '{print $2}' | awk -F '=' '{print $2}')"
    kIFACE="$(echo "$msgDATA" | awk -F' ' '{print $3}' | awk -F '=' '{print $2}')"
    kSRCIP="$(echo "$msgDATA" | awk -F' ' '{print $4}' | awk -F '=' '{print $2}')"
    kPROTO="$(echo "$msgDATA" | awk -F' ' '{print $5}' | awk -F '=' '{print $2}')"
    _LogMsg_ "Knock detected on interface [$kIFACE] into port [${kPORTx}:${kPROTO}] with ID=[$nextID] from SRC=[$kSRCIP]"

    while read -r cfgLINE
    do
        if [ -z "$cfgLINE" ] || \
           echo "$cfgLINE" | grep -qE "^[[:blank:]]*[#].*"
        then continue  #SKIP#
        fi
        cfgLINE="$(echo "$cfgLINE" | sed 's/  \+/  /')"
        thePORTx="$(echo "$cfgLINE" | awk -F' ' '{print $1}')"
        theIFACE="$(echo "$cfgLINE" | awk -F' ' '{print $2}')"
        theCMDx="$(echo "$cfgLINE" | awk -F' ' '{match($0, $3); print substr($0, RSTART)}')"

        if [ -z "$thePORTx" ] || [ -z "$theIFACE" ] || [ -z "$theCMDx" ]
        then continue  #INVALID#
        fi

        thePORTx="$(_NormalizeCSVList_ "$thePORTx")"
        theIFACE="$(_NormalizeCSVList_ "$theIFACE")"
        portIFacesLst="$(echo "$theIFACE" | tr ',' ' ')"
        portNumSeqLst="$(echo "$thePORTx" | tr ',' ' ')"
        portListCount="$(echo "$thePORTx" | awk -F',' '{print NF}')"
        tempNumSeqLst="" ; activeIFaceOK=true ; portNumOK=true

        for pIFace in $portIFacesLst
        do
            if ! _CheckInterface_ "$pIFace" NOLOG
            then activeIFaceOK=false
            elif [ "$pIFace" = "$kIFACE" ]
            then activeIFaceOK=true ; break
            fi
        done

        for pNumber in $portNumSeqLst
        do
            if ! _ValidatePortNumber_ "$pNumber" NOLOG
            then portNumOK=false
            fi
            if _CheckDupPortFound_ "$pNumber" NOLOG 
            then portNumOK=false
            fi
            taggedPort="$(_GetTaggedPortNumber_ "$pNumber")"
            tempNumSeqLst="${tempNumSeqLst:+$tempNumSeqLst }$taggedPort"
        done
        portNumSeqLst="$tempNumSeqLst"

        if [ "$portListCount" -gt 2 ]
        then
            portNumOK=false
            _LogMsg_ "**ERROR**: INVALID number of ports [$thePORTx] found" "$pLogERROR" NOLOG
        fi

        if [ "$portNumOK" = "false" ] || \
           [ "$activeIFaceOK" = "false" ]
        then
            _LogMsg_ "*WARNING*: The port knock entry [$cfgLINE] will be ignored" "$pLogWARNG" NOLOG
            echo
            continue
        fi

        if ! echo "$portIFacesLst" | grep -qw "\b${kIFACE}\b" || \
           ! echo "$portNumSeqLst" | grep -qw "\b${kPORTx}_${kPROTO}\b"
        then continue  #NO MATCH#
        fi

        portNum1="$(echo "$portNumSeqLst" | awk -F' ' '{print $1}')"
        portNum2="$(echo "$portNumSeqLst" | awk -F' ' '{print $2}')"

        if [ "$portListCount" -eq 1 ]
        then
            thePortNum="$portNum1"
        else
            thePortNum=""
            if [ "${kPORTx}_${kPROTO}" = "$portNum1" ]
            then
                _LogMsg_ "Starting port [${portNum1//_/:}] timer"
                /opt/sbin/screen -S "knock_$portNum1" -X quit >/dev/null
                /opt/sbin/screen -dmS "knock_$portNum1" sleep $DOUBLE_KNOCK_WAIT
                srceIPaddr="$kSRCIP"
                break  #Get Next Port in the sequence#
            fi

            if [ "$kSRCIP" = "$srceIPaddr" ] && \
               [ "${kPORTx}_${kPROTO}" = "$portNum2" ] && \
               /opt/sbin/screen -ls "knock_$portNum1" >/dev/null
            then
                _LogMsg_ "Port [${portNum1//_/:}] timer running"
                /opt/sbin/screen -S "knock_$portNum1" -X quit >/dev/null
                #Got Correct Port Sequence#
                thePortNum="$portNum2"
            fi
        fi

        if [ -n "$thePortNum" ] && [ "${kPORTx}_${kPROTO}" = "$thePortNum" ]
        then
            thePortNum="" ; srceIPaddr=""
            _LogMsg_ "Executing [ID=$nextID] CMD: [$theCMDx $thePORTx]" "$pLogWARNG"
            eval $theCMDx "$thePORTx" &
            break  #Get Next Port Knock#
        fi
    done < "$cf"

    sleep "$delayINTERVAL"
    knockWaitNUM="$((knockWaitNUM + delayINTERVAL))"

    # Get retry entry #
    Read_dmesgDATA
    prevID="$(Read_dmesgID checkID)"
done

_ReleaseMutexFLock_

#EOF#
