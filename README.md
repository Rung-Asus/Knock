# Knock
Knock: Router Commands for non-admin users

## To install
ssh into your router and enter the following command:

      curl --retry 3 "https://raw.githubusercontent.com/Rung-Asus/Knock/refs/heads/main/knock.sh" -o /jffs/scripts/knock.sh && chmod 755 /jffs/scripts/knock.sh && sh /jffs/scripts/knock.sh -install


Next update knock.cfg configuration file in the /jffs/addons/knock.d/ folder:


      nano /jffs/addons/knock.d/knock.cfg

Format of file is:

Port Number \<space> Interface(s) [comma separated] \<space> Command to execute [to end of line]
          
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

## Acknowledgments
Many thanks to @Viktor Jaep for all his help, input and testing of this script!

Portions in this script were derved from @Viktor Jaep's awesome Tailmon script

Original concept credit to @RMerlin (https://www.snbforums.com/threads/wake-on-lan-per-http-https-script.7958/post-47811)
