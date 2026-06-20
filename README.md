# Knock
Knock: Router Commands for non-admin users

## v3.0.0
### Updated on 2026-Jun-19

## Installation
ssh into your router and enter the following command:

    curl --retry 3 "https://raw.githubusercontent.com/Rung-Asus/Knock/main/knock.sh" -o /jffs/scripts/knock.sh && chmod 755 /jffs/scripts/knock.sh && sh /jffs/scripts/knock.sh -install


Next update the **knock.cfg** configuration file in the **/jffs/addons/knock.d/** directory:

    nano /jffs/addons/knock.d/knock.cfg

Format of file is:

    Port Number(s)[comma separated] <space> Interface(s)[comma separated] <space> Command to execute [to end of line]
          
Finally run the following command: 

    /jffs/scripts/knock.sh -start

Users can now execute commands by sending port knocks

(e.g. for main LAN interface command, enter browser url: http://192.168.50.1:44444)

## To Update Configuration
Run:

    /jffs/scripts/knock.sh -stop
        
Then update the **/jffs/addons/knock.d/knock.cfg** config file.

Finally run:

    /jffs/scripts/knock.sh -start

## Uninstallation
run:

    /jffs/scripts/knock.sh -uninstall


## Port Knocks using UDP and TCP protocols

Users can define Port Knock rules using either **UDP** or **TCP** protocol, or a combination of those.

In the configuration file, users must indicate a **UDP** port with either a ':U' or ':UDP' tag as shown below:

```sh
   50102:U,50104:U,50108:U br0 command_to_send
   50202:UDP,50204:UDP,50208:UDP br0 command_to_send
```

When using **TCP** ports, no tags are required since the default setting is TCP, but users may still tag TCP ports if they so desire with either a ':T' or ':TCP' tag like so: 

```sh
   50102:T,50104:T,50108:T br0 command_to_send
   50202:TCP,50204:TCP,50208:TCP br0 command_to_send
```

Note that only uppercase letters are considered valid; otherwise, the rule is ignored, and an error will be reported when checking/parsing the configuration file.

When adding/editing a Port Knock rule using the built-in "editor" function, the code will check and automatically modify lowercase tags to uppercase to prevent such user errors.


## Multi-Port Knock Sequences

Users can define Multi-Port Knock rules using up to **6** unique ports in the sequence. A port sequence may use a combination of **UDP** and **TCP** ports.

Example:

    50101:UDP,50202:TCP,50303:UDP,50404:TCP,50505:UDP br0 command_to_send


Note that each Port Knock rule is expected to use unique port numbers; otherwise, rules containing duplicate ports are considered invalid. However, using the same port number with a different protocol tag would **not** be considered a duplicate. For instance, ports "50123:UDP" and "50123:TCP" are treated as different ports.


## Entware is **not** required

The script no longer requires to have Entware installed. Installing and using the Entware 'screen' utility is now completely optional. Instead, the script creates a built-in background process running as a daemon.


## Example Use Cases

1. Allow a user on local LAN, using the WireGuard server, or Tailscale server to wake up a specific PC

Put the following line in the config file:

```sh
    44444 br0,lo,wgs1 ether-wake -i br0 xx:xx:xx:xx:xx:xx
```

The user now executes this command with http://192.168.50.1:44444, for example

2. Allow same user to reboot router

```sh
    44445 br0,lo,wgs1 reboot
```

3. Allow a user on the local LAN to run a custom script that enables something (e.g. a VPN Director rule)

```sh
    44446 br0 /jffs/scripts/enable-example.sh
```

4. Same user to run a complementary disable script

```sh
    44447 br0 /jffs/scripts/disable-example.sh
```

Other use case possibilities from @Victor Jaep include:

1. Kick off a backup -- like using "sh /jffs/scripts/backupmon.sh -backup"
2. Turn lights on and off with JGrana's huetil and uKasa apps
3. Initiate a WAN failover with the wan_failover script

## Acknowledgments
Many thanks to @Viktor Jaep for all his help, input and testing of this script!

Portions in this script were derved from @Viktor Jaep's awesome Tailmon script

Original concept credit to @RMerlin (https://www.snbforums.com/threads/wake-on-lan-per-http-https-script.7958/post-47811)
