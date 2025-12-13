# Knock
Knock: Router Commands for non-admin users

## To install
ssh into your router and enter the following command:

      curl --retry 3 "https://raw.githubusercontent.com/Rung-Asus/Knock/refs/heads/main/knock.sh" -o /jffs/scripts/knock.sh && chmod 755 /jffs/scripts/knock.sh && sh /jffs/scripts/knock.sh -install


Next update knock.cfg configuration file in the /jffs/addons/knock.d/ folder:


      nano /jffs/addons/knock.d/knock.cfg

Format of file is:

Port Number \<space> Interface(s) [comma separated] \<space> Command to execute [to end of line] (see example section)
          
Finally run the following command: 

      /jffs/scripts/knock.sh -start

Users can now execute commands by sending port knocks

(e.g. for main lan interface command, enter browser url: http://192.168.50.1:44444)

## To Update Configuration
Run:

      /jffs/scripts/knock.sh -stop
        
Then update '/jffs/addons/knock.d/knock.cfg'

Finally run:

      /jffs/scripts/knock.sh -start

## To Uninstall
run:

      /jffs/scripts/knock.sh -uninstall

## Example Use Cases

1. Allow a user on local LAN, using the wireguard server, or Tailscale server to wake up a specific PC

Put the following line in the config file:

44444 br0,lo,wgs1 ether-wake -i br0 xx:xx:xx:xx:xx:xx

The user now executes this command with http://192.168.50.1:44444, for example

2. Allow same user to reboot router

44445 br0,lo,wgs1 reboot

3. Allow a user on the local LAN to run a custom script that enables something (e.g. a VPN Director rule)

44446 br0 /jffs/scripts/enable-example.sh

4. Same user to run a complementary disable script

44447 br0 /jffs/scripts/disable-example.sh

Other use case possibilities from @Victor Jaep include:

1. Kick off a backup -- like using "sh /jffs/scripts/backupmon.sh -backup"
2. Turn lights on and off with JGrana's huetil and uKasa apps
3. Initiate a WAN failover with the wan_failover script

## Acknowledgments
Many thanks to @Viktor Jaep for all his help, input and testing of this script!

Portions in this script were derved from @Viktor Jaep's awesome Tailmon script

Original concept credit to @RMerlin (https://www.snbforums.com/threads/wake-on-lan-per-http-https-script.7958/post-47811)
