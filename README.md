# Knock
Knock: Router Commands for non-admin users

## To install
ssh into your router and enter the following command:

      curl -L -s -k -O https://raw.githubusercontent.com/Rung-Asus/Knock/refs/heads/main/knock.sh && sh knock.sh -install

Next update knock.cfg configuration file in the /jffs/addons/knock/ folder

Format of file is:

Port Number \<space> Interface(s) [comma separated] \<space> Command to execute [to end of line]
          
Finally run the following command: 

      /jffs/addons/knock.sh -start

Users can now execute commands by sending port knocks

(e.g. for main lan interface command, enter browser url: http://192.168.50.1:44444)

## To Update Configuration
Run:
      /jffs/addons/knock/knock.sh -stop
        
Then update '/jffs/addons/knock/knock.cfg'

Finally run:
      /jffs/addons/knock/knock.sh -start

## To Uninstall
run:
      /jffs/addons/knock/knock.sh -uninstall

