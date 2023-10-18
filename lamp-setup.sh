#!/usr/bin/bash

# LAMP SERVER PROVISION SETUP

# PREPARE THE WORKING DIRECTORY

if [[ $PWD == ~/altschool/vagrant/boxes/ubuntu22.04-LTS ]]; then
   echo "running script..."
elif [[ -d ~/altschool/vagrant/boxes/ubuntu22.04-LTS ]]; then
     cd ~/altschool/vagrant/boxes/ubuntu22.04-LTS
else
   mkdir ~/altschool/vagrant/boxes/ubuntu22.04-LTS && cd ~/altschool/vagrant/boxes/ubuntu22.04-LTS
fi

# INITIALIZE VAGRANT IN THE CURRENT DIRECTORY

if [[ -a Vagrantfile ]]; then
   echo "Vagrantfile exist"
else
   vagrant init ubuntu/jammy64
fi

# PROVISIONING VAGRANTFILE

sed -i '$d' Vagrantfile

cat>>Vagrantfile<<'EOL'
# Multi-machine setup
    config.vm.define "master" do |subconfig|
      subconfig.vm.box = "ubuntu/jammy64"
      subconfig.vm.hostname = "master"
      subconfig.vm.network :private_network, ip: "192.168.56.30"
    end

    config.vm.define "slave" do |subconfig|
      subconfig.vm.box = "ubuntu/jammy64"
      subconfig.vm.hostname = "slave"
      subconfig.vm.network :private_network, ip: "192.168.56.35"
    end

    config.vm.define "loadbalancer" do |lb|
      lb.vm.box = "ubuntu/jammy64"
      lb.vm.network :private_network, ip: "192.168.56.25"
    end

# Provisioning scripts for master and slave nodes

    config.vm.provision "shell", inline: <<-SHELL
      sudo apt upgrade -y
    SHELL

    config.vm.provision "shell", inline: <<-SHELL
      sudo apt update -y
    SHELL

    config.vm.provision "shell", inline: <<-SHELL
      sudo apt install -y apache2
    SHELL

    config.vm.provision "shell", inline: <<-SHELL
      sudo apt install -y mysql-server
    SHELL

    config.vm.provision "shell", inline: <<-SHELL
      sudo apt install -y php libapache2-mod-php php-mysql 
    SHELL

    config.vm.provision "shell", inline: <<-SHELL
      sudo apt install -y net-tools
    SHELL

    config.vm.provision "shell", inline: <<-SHELL
      sudo apt install -y openssh-server
    SHELL

    config.vm.provision "shell", inline: <<-SHELL
      sudo apt install -y openssh-client
    SHELL

    config.vm.provision "shell", inline: <<-SHELL
      sudo a2enmod proxy
      sudo a2enmod proxy_http
      sudo a2enmod proxy_balancer
      sudo a2enmod lbmethod_byrequets
      sudo systemctl restart apache2
    SHELL

# Provisioning for the load balancer

    lb.vm.provision "shell", inline: <<-SHELL
      sudo systemctl restart apache2
      sudo chown vagrant:vagrant /etc/apache2/sites-available/000-default.conf
      sudo cat>/etc/apache2/sites-available/000-default.conf<<'EOL'
	<VirtualHost *:80>
		<Proxy balancer://mycluster>
		  BalancerMember http://192.168.56.30:80
		  BalancerMember http://192.168.56.35:80
		</Proxy>

		ProxyPreserveHost On
		ProxyPass / balancer://mycluster/
		ProxyPassReverse / balancer://mycluster/
	</VirtualHost>
	EOL

      sudo systemctl restart apache2

    lb.vm.provision "SHELL", inline: <<-SHELL
      sudo chown vagrant:vagrant /etc/hosts

      sudo cat>>/etc/hosts<<'EOF'

	192.168.56.25 lb.server.com lb
	192.168.56.30 web1.server.com web1
	192.168.56.35 web2.server.com web2
      EOF

     sudo systemctl restart apache2
end

EOL

# SPIN UP LAMP SERVER

vagrant up

function setupslave() {
        vagrant ssh slave -c "sudo useradd -m -s /bin/bash altschool"
        vagrant ssh slave -c 'echo -e "123456\n123456" | sudo passwd altschool'
        vagrant ssh slave -c "sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config"
        vagrant ssh slave -c "sudo systemctl restart sshd"
  }
  setupslave

 function setupmaster() {
	vagrant ssh master -c "sudo useradd -m -G sudo -s /bin/bash altschool"
        vagrant ssh master -c 'echo -e "123456\n123456" | sudo passwd altschool'
        vagrant ssh master -c "sudo apt install -y sshpass"
        vagrant ssh master -c "sudo su - altschool -c 'echo "" | ssh-keygen -t rsa -f ~/.ssh/id_rsa'"
        vagrant ssh master -c "sudo su - altschool -c 'sshpass -p '123456' ssh-copy-id -o StrictHostKeyChecking=no altschool@192.168.56.35'"
	vagrant ssh master -c "echo 'altschool ALL=(ALL) NOPASSWD: /bin/* /*' | sudo tee -a /etc/sudoers"
	vagrant ssh slave -c "echo 'altschool ALL=(ALL) NOPASSWD: /bin/* /*' | sudo tee -a /etc/sudoers"
        vagrant ssh slave -c "sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config"
	vagrant ssh slave -c "sudo sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config"
        vagrant ssh slave -c "sudo systemctl restart sshd"
        vagrant ssh master -c "sudo su - altschool -c 'ssh altschool@192.168.56.35'"
 }
 setupmaster
