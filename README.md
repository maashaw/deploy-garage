# Using this tool to deploy your docker host

This tool is designed to make it easy to securely deploy a new containerised docker application. There are a few simple steps to follow.

1. Clone (or create) an instance of Ubuntu Server 24.04 LTS
  This will require Git. If it is not already installed in the clone, or if you are starting from install media, you will need to run `sudo apt install git`
  Note: The script assumes that default LUKS and root passwords are in place: `default-luks-key` and `default-login-key`, respectively. If these are not correct, you will need to change the contents of deploy-garage/ephemeral.
  NB: The .pw files are simply text files, but should *not* end with a newline (unless your password does!). You can do this using `printf "your string" > filename.pw`
2. Run init.sh
  Simply `cd ./deploy-garage` and then type `./init.sh`. No parameters are required - it will generate new passwords, keys, and identifiers as part of the script. New credentials will be saved in 
3. Wait
4. Log into the VM using SSH
  You may need to refer to your hypervisor to identify the DHCP-assigned address. Note the machine's credentials stored in ~/deploy-garage/ephemeral. You may wish to record these somewhere secure, then `shred` the contents of this directory.
5. Machine-specific configuration
  - [ ] Configure ~/garage/vols/garage.toml by adding your bootstrap_peers (if not already populated)
  - [ ] Check the rest of ~/garage/vols/garage.toml is suitable for your needs
  - [ ] Configure ~/garage/docker-config.yml by adding your DNS api key for DNS challenges
  - [ ] Check that ~/garage/docker-config.yml is suitable for your needs
  - [ ] Enter your DNS parameters into ~/caddy/config/Caddyfile
  - [ ] Check the rest of ~/caddy/config/Caddyfile is suitable for your needs
6. Start your engines!
  ```sudo docker compose --file ~/garage/docker-compose.yml pull
     sudo docker compose --file ~/garage/docker-compose.yml up -d```
