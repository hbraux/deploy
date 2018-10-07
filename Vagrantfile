BOX_DESCRIPTION = "CentOS7"
BOX_NAME = "work"
BOX_DOMAIN = "hostonly.com"
BOX_RAM = "2048"  
BOX_CPU = "1" 
BOX_IP = "192.168.56.2"
# change to false to mount the Vagrant folder
BOX_NOSYNC = true
PASSWORD = "password"

# Ansible playbook and options
PLAYBOOK_ARGS="default.yml --tags userenv,docker,emacs"

Vagrant.configure("2") do |config|
        passkey = PASSWORD
 	if File.file?("key.pub") 
		passkey = File.readlines("key.pub").first.strip
	end
	config.vm.define BOX_NAME
	config.vm.box = "centos/7"
	config.vm.box_check_update = false
	config.vm.network :private_network, ip: BOX_IP
	config.vm.hostname = "#{BOX_NAME}.#{BOX_DOMAIN}"
	config.vm.synced_folder ".", "/vagrant", disabled: BOX_NOSYNC
	config.vm.provider "virtualbox" do |vb|
		vb.name = BOX_NAME
		vb.customize ["modifyvm", :id, "--memory", BOX_RAM]
		vb.customize ["modifyvm", :id, "--cpus", BOX_CPU]
		vb.customize ["modifyvm", :id, "--audio", "none"]
		vb.customize ["modifyvm", :id, "--description", "#{BOX_DESCRIPTION}
Add this line to your Windows hosts file: #{BOX_IP} #{BOX_NAME}.#{BOX_DOMAIN}
Login with putty as user #{ENV['USERNAME']}/#{PASSWORD}"]
	end
	config.vm.provision 'shell', inline: "curl -s https://raw.githubusercontent.com/hbraux/deploy/master/deploy.sh | bash -s #{ENV['USERNAME']} '#{passkey}' #{ENV['CENTOS_MIRROR']} #{PLAYBOOK_OPTS}"
end

