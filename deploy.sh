#!/bin/bash
# This generic script is downloaded and executed by Vagrant provision
# It installs ansible, runs the embedded playbook which creates a user and 
# clones the Git repo, then runs the Ansible script default.yml 
# Input arguments: 
#  $1  Unix user to be created
#  $2  password or public SSH key (id-rsa xxx)
#  $3  fqdn or @IP of a CentOS mirror (optional)
#  $4+ ansible playbook and options

# the script can be run locally from the Git repo 
if [[ -f ./default.yml ]]; then
  echo "(deploy.sh) LOCAL MODE"
  if [[ -f $1 && ${1#*.} == yml ]]; then 
      playbook=$1
      shift
  else
      playbook=default.yml
  fi
  ansible-playbook --connection=local -i localhost, $playbook $* 
  exit
fi

echo "(deploy.sh) BEGIN ============================================================="

if [[ $# -lt 2 ]] ; then
   echo "(deploy.sh) expecting USERNAME PASSWORD [CENTOS_MIRROR] [PLAYBOOK] [PLAYBOOK_OPTS...]"
   exit 1
fi
user=$1
shift
pass=$1
shift
 
if [[ -n $http_proxy ]] ; then 
  echo "(deploy.sh) using proxy variables http_proxy=$http_proxy https_proxy=$https_proxy no_proxy=$no_proxy"
fi

# is next argument a FQDN or not a playbook
if [[ -n $1 && ${1#*.} != yml && ${1:0:1} != - ]] ; then
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

if [[ ! -x /usr/bin/ansible-playbook ]]; then 
   echo "(deploy.sh) installing Ansible"
   yum install -y -q --nogpg ansible
fi

cat >vagrant.yml <<EOF
- hosts: 127.0.0.1
  connection: local
  become: yes
  tasks:
    - name: install must-have packages
      yum:
        name: "{{ item }}"
      with_items:
        - sudo
        - git
        - make
        - nano

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

    - name: create directory .ssh
      file:
        path: /home/{{ username }}/.ssh
        owner: "{{ username }}"
        state: directory
        mode: 0700

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
        path: /home/{{ username }}/git
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
      when: centos_mirror != "" 
        
    - name: Add Epel repo (using yum)
      yum:
        name: epel-release
      when: centos_mirror == ""
 
    - name: install Epel packages
      yum:
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
        
    - name: update /etc/hosts
      lineinfile:
        path: /etc/hosts
        regexp: "^.*{{ fqdn }}.*$"
        line: "{{ ip }} {{ fqdn }}"

    - name: check for rpm files in /vagrant/install
      find:
        path: /vagrant/install
        patterns: "*.rpm"
      ignore_errors: yes
      register: rpm_files

    - name: install rpm files from /vagrant/install
      yum:
        name: "{{ item }}"
      with_items: "{{ rpm_files.files|map(attribute='path')|list }}"
      when: rpm_files.matched > 0

  handlers:
    - name: restart sshd
      service:
        name: sshd
        state: restarted
EOF

echo "(deploy.sh) executing as root embedded playbook"
ansible-playbook vagrant.yml -e username=$user -e "password=\"$pass\"" -e centos_mirror="$mirror" -i localhost,

echo "(deploy.sh) SETUP ============================================================="

if [[ ${1#*.} == yml ]]; then
  playbook=/home/$user/git/deploy/$1
  shift
else
  playbook=/home/$user/git/deploy/default.yml
fi
if [[ ! -f $playbook ]] ; then 
  echo "ERROR: file $playbook doesnot exist"; exit 1
fi

opts="--connection=local -i $(uname -n), $*"
echo "(deploy.sh) executing as user $user: ansible-playbook $playbook $opts"
su - $user -c "ansible-playbook $playbook $opts"

echo "(deploy.sh) Cleansing /vagrant"
rm -fr /vagrant

echo "(deploy.sh) END ==============================================================="






