# deploy

A set of Ansible scripts to create a [CentOS 7](https://www.centos.org/) Linux VM with technical components

### Installation 

Option A: create a new VM for Windows
* Install [Virtualbox](https://www.virtualbox.org/)
* Install [Vagrant](https://www.vagrantup.com/downloads.html)
* Install [Kitty](http://www.9bis.net/kitty/), a nice fork of putty
* If you have a Proxy: install Vagrant [Proxy plugin](https://github.com/tmatilai/vagrant-proxyconf) wicth command `vagrant plugin install vagrant-proxyconf` and define Windows environment variables VAGRANT_HTTP_PROXY, VAGRANT_HTTPS_PROXY and VAGRANT_NO_PROXY
* Optionnaly define Windows environment variable CENTOS_MIRROR to your prefered CentOS mirror (fqdn)
* Download [Vagrantfile](https://raw.githubusercontent.com/hbraux/linux-vm/master/Vagrantfile) from the repo and save it to a work directory
* Adapt the parameters in the header ot the file
* Optionnaly create SSH keys for Putty using [Puttygen](https://www.ssh.com/ssh/putty/windows/puttygen) and save the public key as `key.pub` in the work directory 
* Open a CMD prompt, go to the work directory, run `vagrant up` and wait for VM creation process to complete. If the process stops at ```Running: inline script``` it's likely due to an internet connection issue.
* Connect with kitty to 192.168.56.2 (or whatever IP you specified in the file) with your Windows's username and either the private key file or the defaut password in Vagrantfile. This UNIX user has sudo access.

Option B: from an existing VM
* clone the git repo and run setup.sh

### Roles
The installation script `deploy.sh` supports the following Playbook and ansible roles to be provided as arguments with --tags xxx

* to be completed


