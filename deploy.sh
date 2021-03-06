#!/bin/bash
# This generic script is downloaded and executed by Vagrant provision
# It installs ansible, runs the embedded playbook which creates a user and 
# clones this Git repo, then runs the Ansible playbook given in arguments
# Input arguments: 
#  $1  Unix user to be created
#  $2  password or public SSH key (id-rsa xxx)
#  $3  fqdn or @IP of a CentOS mirror (optional)
#  $4+ ansible playbook and options

# if the script was not invoked by vagrant, it's a local execution
who am i
if [[ $USER != root ]]; then
  if [[ ${1##*.} == yml ]]; then 
    if [[ -f $1 ]]; then
      playbook=$1
    else 
      playbook=$HOME/git/deploy/$1
    fi
    shift
  else
    playbook=$HOME/git/deploy/all.yml
  fi
  echo "(deploy.sh) Executing on localhost: ansible-playbook $playbook $*"
  ansible-playbook --connection=local -i localhost, $playbook $* 
  exit
fi

echo "(deploy.sh) BEGIN ============================================================="

if [[ $# -lt 3 ]] ; then
   echo "(deploy.sh) expecting USERNAME PASSWORD [CENTOS_MIRROR] PLAYBOOK [PLAYBOOK_OPTS]"
   exit 1
fi
user=$1
shift
pass=$1
shift
 
if [[ -n $http_proxy ]] ; then 
  echo "(deploy.sh) using proxy variables http_proxy=$http_proxy https_proxy=$https_proxy no_proxy=$no_proxy"
fi

# if next argument is not a playbook, then it's a FQDN
if [[ ${1#*.} != yml ]] ; then
  mirror=$1
  shift
  grep -q $mirror /etc/yum.repos.d/CentOS-Base.repo 
  if [[ $# -ne 0 ]] ; then 
      echo "(deploy.sh) setting $mirror as baseurl in CentOS-Base.repo"
      sed -i -e "s~gpgcheck=1~gpgcheck=0\nproxy=_none_~g;s~^mirrorlist=.*~~g;s~#baseurl=http://mirror.centos.org~baseurl=http://$mirror~g" /etc/yum.repos.d/CentOS-Base.repo
  fi
else
  mirror=""
fi

set -e

ostype=$(sed -n 's/^ID=\(.*\)/\1/p' /etc/os-release | sed 's/"//g')

if [[ ! -x /usr/bin/ansible-playbook ]]; then 
   echo "(deploy.sh) installing Ansible"
   case $ostype in
     centos) yum install -y -q --nogpg ansible;;
     ubuntu) apt-get install -qy ansible;;
     *) echo "Unsupported OS type $ostype"; exit 1;;
   esac
fi

cat >vagrant.yml <<'EOF'
- hosts: 127.0.0.1
  connection: local
  become: yes
  tasks:
    - name: install must-have packages
      package:
        name: "{{ item }}"
      with_items: ["sudo","git","nano"]

    - name: ensure that wheel group exist
      group:
        name: wheel

    - name: allow passwordless sudo for wheel group
      lineinfile:
        dest: /etc/sudoers
        regexp: '^%wheel'
        line: '%wheel ALL=(ALL) NOPASSWD: ALL'
        validate: 'visudo -cf %s'

    - name: create user {{ username }}
      user:
        name: "{{ username }}"
        group: users
        groups: wheel

    - name: create user's directories
      file:
        path: /home/{{ username }}/{{ item }}
        owner: "{{ username }}"
        state: directory
        mode: 0700
      with_items: [".ssh", "bin", "git"]

    - name: add public key to user {{ username }}
      authorized_key:
        user: "{{ username }}"
        key: "{{ password }}"
      when: password is match ("ssh-rsa .*")

    - name: update password for user {{ username }}
      user:
        name: "{{ username }}"
        password: "{{ password | password_hash('sha512') }}"
        update_password: always
      when: password is not match ("ssh-rsa .*")

    - name: allow PasswordAuthentication
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^PasswordAuthentication '
        line: 'PasswordAuthentication yes'
      notify:
        - restart sshd
      when: password is not match ("ssh-rsa .*")

    - name: get hostname
      shell: uname -n 
      register: hostname_cmd
      changed_when: false

    - fail:
        msg: hostname {{ hostname_cmd.stdout }} is not a FQDN
      when: not hostname_cmd.stdout | regex_search('.+\..+\.')

    - name: update .ssh/config
      blockinfile:
        path: /home/{{ username }}/.ssh/config
        create: yes
        owner: "{{ username }}"
        block: |
          Host *.{{ hostname_cmd.stdout.split('.', 1)[1] }}
            StrictHostKeyChecking no
            UserKnownHostsFile=/dev/null

    - name: clone the git repo
      git:
        repo: https://github.com/hbraux/deploy.git
        dest: /home/{{ username }}/git/deploy

    - name: update the owner
      file:
        path: /home/{{ username }}
        owner: "{{ username }}"
        group: users
        recurse: yes

    - name: Add Epel repo (using mirror)
      yum_repository:
        name: epel
        description: EPEL YUM repo
        baseurl: http://{{ centos_mirror }}/fedora/epel/\$releasever/\$basearch/
        gpgcheck: no
        proxy: _none_
      when: ansible_distribution == 'CentOS' and centos_mirror != "" 
        
    - name: Add Epel repo (using yum)
      package:
        name: epel-release
      when: centos_mirror == ""
 
    - name: install Epel packages
      package:
        name: "{{ item }}"
      with_items:
        - python-pip 

    - name: get host-only IP from eth1
      shell: ip address show dev eth1 | sed -n  's~^.*inet \([0-9\.]*\)/.*$~\1~p'
      register: ip_cmd
      changed_when: false

    - set_fact:
        ip: "{{ ip_cmd.stdout }}"
        fqdn: "{{  hostname_cmd.stdout }}"
        
    - name: add {{ fqdn }} to /etc/hosts 
      lineinfile:
        path: /etc/hosts
        regexp: "^.*{{ fqdn }}.*$"
        line: "{{ ip }} {{ fqdn }}"

    - set_fact:
        hostip: "{{ ip | regex_replace('^(.*)\\.\\d+$', '\\1.1')  }}"
        hostfqdn: "{{  fqdn | regex_replace('^\\w+\\.(.*)$', 'host.\\1') }}"

    - name: add {{ hostfqdn }} to /etc/hosts 
      lineinfile:
        path: /etc/hosts
        regexp: "^.*{{ hostfqdn }}.*$"
        line: "{{ hostip }} {{ hostfqdn }} host"

    - name: check for rpm files in /vagrant/install
      find:
        path: /vagrant/install
        patterns: "*.rpm"
      ignore_errors: yes
      register: rpm_files

    - name: install rpm files from /vagrant/install
      package:
        name: "{{ item }}"
      with_items: "{{ rpm_files.files|map(attribute='path')|list }}"
      when: rpm_files.matched > 0

    - name: update /etc/motd
      shell: echo -e "\n**************************************************************************\nWELCOME!\n\nThis box was created with Vagrant and https://github.com/hbraux/deploy\n**************************************************************************\nUser {{ username }} has sudo permissions\nRun ~/git/deploy/deploy.sh finalize.yml to complete installation">/etc/motd

  handlers:
    - name: restart sshd
      service:
        name: sshd
        state: restarted
EOF

echo "(deploy.sh) executing as root embedded playbook"
ansible-playbook vagrant.yml -e username=$user -e "password=\"$pass\"" -e centos_mirror="$mirror" -i localhost,

echo "(deploy.sh) SETUP ============================================================="

playbook=/home/$user/git/deploy/$1
shift
if [[ ! -f $playbook ]] ; then 
  echo "ERROR: file $playbook doesnot exist"; exit 1
fi

opts="--connection=local -i $(uname -n), -e ansible_cache=/vagrant/cache $*"
echo "(deploy.sh) executing as user $user: ansible-playbook $playbook $opts"
su - $user -c "ansible-playbook $playbook $opts"

echo "(deploy.sh) Cleansing /vagrant"
rm -fr /vagrant

echo "(deploy.sh) END ==============================================================="
