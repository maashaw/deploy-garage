# What does this script do?
This tool is designed to make it easy to securely deploy a new containerised docker application, using a cloned Ubuntu Server 22.04 LTS instance.

It assumes that you want
  - Full disk encryption with LUKS
  - Network-bound decryption with Clevis/Tang
  - Passwordless SSH access

# Using this tool to deploy your docker host

 There are a few simple steps to follow.

1. Clone (or create) an instance of Ubuntu Server 24.04 LTS

  This will require Git. If it is not already installed in the clone, or if you are starting from install media, you will need to run `sudo apt install git`
  Note: The script assumes that default LUKS and root passwords are in place: `default-luks-key` and `default-login-key`, respectively. If these are not correct, you will need to change the contents of deploy-garage/ephemeral.
  NB: The .pw files are simply text files, but should *not* end with a newline (unless your password does!). You can do this using `printf "your string" > filename.pw`
  
2. Configure any parameters that are neccessary before running the script

  - [ ] Configure ~/deploy-garage/tang.json to point to your tang servers, for automatic network-bound LUKS decryption
  - [ ] Ensure that an SSH server is present on the machine, and that your keys (and only your keys) are present in ~/deploy-garage/keys
  
3. Run init.sh

  Simply `cd ./deploy-garage` and then type `./init.sh`. No parameters are required - it will generate new passwords, keys, and identifiers as part of the script.
  
4. Wait

  This will take a little bit of time - the script has to re-encrypt the whole disk, which is the slowest step.
  
5. Log into the VM using SSH

  When the script completes, it will reboot the host. If you have correctly configured 
  You may need to refer to your hypervisor to identify the DHCP-assigned address. Note the machine's credentials stored in ~/deploy-garage/ephemeral. You may wish to record these somewhere secure, then `shred` the contents of this directory.
  
6. Machine-specific configuration

  - [ ] Configure ~/garage/vols/garage.toml by adding your bootstrap_peers (if not already populated)
  - [ ] Check the rest of ~/garage/vols/garage.toml is suitable for your needs
  - [ ] Configure ~/garage/docker-config.yml by adding your DNS api key for DNS challenges
  - [ ] Check that ~/garage/docker-config.yml is suitable for your needs
  - [ ] Enter your DNS parameters into ~/caddy/config/Caddyfile
  - [ ] Check the rest of ~/caddy/config/Caddyfile is suitable for your needs
  
7. Start your engines!

  ```
  sudo docker compose --file ~/garage/docker-compose.yml pull
  sudo docker compose --file ~/garage/docker-compose.yml up -d
  ```

# Adapting this for your own deployment

  - [ ] Prepare your base image (Ubuntu Server 22.04 LTS with OpenSSH, Git, and LUKS FDE)
  - [ ] Replace the public keys in /keys
  - [ ] Replace the bootstrap nodes in /config/garage-node.list
  - [ ] Replace the tang configuration in /config/tang.json
  - [ ] Review the docker-compose.yml configuration at /payload/garage/docker-compose.yml
  - [ ] Review the garage.template.toml configuration at /payload/garage/garage.template.toml
  - [ ] Review the caddyfile configuration at /payload/caddy/conf/Caddyfile
