# Knock
Knock: Router Commands for non-admin users

To install, ssh into your router and enter the following command:

      curl -L -s -k -O https://raw.githubusercontent.com/Rung-Asus/Knock/refs/heads/main/knock.sh && sh knock.sh -install

Next update knock.cfg configuration file in the /jffs/addons/knock/ folder

Format of file is:

Port Number <space> Interface(s) [comma separated] <space> Command to execute [to end of line]
          
Finally run the following command: 

      /jffs/addons/knock.sh -start
