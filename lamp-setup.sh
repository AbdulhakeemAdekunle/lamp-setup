#!/usr/bin/bash

# LAMP SERVER PROVISION SETUP

# PREPARE THE WORKING DIRECTORY

if [[ $PWD == ~/altschool/vagrant/boxes/ubuntu22.04-LTS ]]; then
   echo "running script..."
elif [[ -d ~/altschool/vagrant/boxes/ubuntu22.04-LTS ]]; then
   cd ~/altschool/vagrant/boxes/ubuntu22.04-LTS || exit
else
   mkdir ~/altschool/vagrant/boxes/ubuntu22.04-LTS && cd ~/altschool/vagrant/boxes/ubuntu22.04-LTS || exit
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
  config.vm.define "master" do |master|
    master.vm.box = "ubuntu/jammy64"
    master.vm.hostname = "master"
    master.vm.network :private_network, ip: "192.168.56.30"
  end

  config.vm.define "slave" do |slave|
    slave.vm.box = "ubuntu/jammy64"
    slave.vm.hostname = "slave"
    slave.vm.network :private_network, ip: "192.168.56.35"
  end

  config.vm.provider "virtualbox" do |vb|
    vb.memory = "1024"
    vb.cpus = "1"
  end

# Provisioning scripts for master and slave node

  config.vm.provision "shell", inline: <<-SHELL
    sudo apt upgrade -y
    sudo apt update -y
    sudo apt install -y apache2
    sudo apt install -y mysql-server
    sudo apt install -y php libapache2-mod-php php-mysql 
    sudo apt install -y net-tools
    sudo apt install -y openssh-server
    sudo apt install -y openssh-client
  SHELL

  config.vm.provision "shell", inline: <<-SHELL
    sudo a2enmod proxy
    sudo a2enmod proxy_http
    sudo a2enmod proxy_balancer
    sudo a2enmod lbmethod_byrequests
    sudo systemctl restart apache2
  SHELL

  config.vm.define "loadbalancer" do |lb|
    lb.vm.box = "ubuntu/jammy64"
    lb.vm.network :private_network, ip: "192.168.56.25"
    lb.vm.provision "shell", inline: <<-SHELL

# Define the Apache configuration and hosts
CONF=$(cat <<'CONF_EOL'
<VirtualHost *:80>
    <Proxy balancer://mycluster>
      BalancerMember http://192.168.56.30:80
      BalancerMember http://192.168.56.35:80
    </Proxy>

    ProxyPreserveHost On
    ProxyPass / balancer://mycluster/
    ProxyPassReverse / balancer://mycluster/
</VirtualHost>
CONF_EOL
)

HOSTS=$(cat <<'HOST_EOL'
192.168.56.25 lb.server.com lb
192.168.56.30 web1.server.com web1
192.168.56.35 web2.server.com web2
HOST_EOL
)

# Write the content to the respective files
echo "$CONF" | sudo tee /etc/apache2/sites-available/000-default.conf
echo "$HOSTS" | sudo tee -a /etc/hosts

    SHELL

  end

end
EOL

# SPIN UP LAMP SERVER

vagrant up

function setupslave() {
 vagrant ssh slave -c "sudo useradd -m -s /bin/bash altschool"
 vagrant ssh slave -c 'echo -e "123456\n123456" | sudo passwd altschool'
 vagrant ssh slave -c "sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config"
 vagrant ssh slave -c "sudo systemctl restart sshd"
 vagrant ssh slave -c "echo 'altschool ALL=(ALL) NOPASSWD: /bin/* /*' | sudo tee -a /etc/sudoers"
 vagrant ssh slave -c "sudo chown vagrant:vagrant /var/www/html/index.html"
 vagrant ssh slave -c "sudo sed -i 's/Apache2 Default Page/Apache2 Default Page on Master Node/' /var/www/html/index.html"
 vagrant ssh slave -c "sudo systemctl restart apache2"
}
setupslave

function securemysql() {
 # Start the server if it is not running
 vagrant ssh slave -c "sudo systemctl start mysql"
 # Assign a password for the initial MySQL root account
 vagrant ssh slave -c "sudo mysql -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY 'Altschool@2';\""
 # Remove anonymous users
 vagrant ssh slave -c "sudo mysql -e \"DELETE FROM mysql.user WHERE User='';\""
 # Disallow root login remotely
 vagrant ssh slave -c "sudo mysql -e \"DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');\""
 # Remove test database and access to it
 vagrant ssh slave -c "sudo mysql -e \"DROP DATABASE IF EXISTS test;\""
 vagrant ssh slave -c "sudo mysql -e \"DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';\""
 # Reload privilege tables now
 vagrant ssh slave -c "sudo mysql -e \"FLUSH PRIVILEGES;\""
}
securemysql

function setupmaster() {
 vagrant ssh master -c "sudo useradd -m -G sudo -s /bin/bash altschool"
 vagrant ssh master -c 'echo -e "123456\n123456" | sudo passwd altschool'
 vagrant ssh master -c "sudo apt install -y sshpass"
 vagrant ssh master -c "sudo su - altschool -c 'echo "" | ssh-keygen -t rsa -f ~/.ssh/id_rsa'"
 vagrant ssh master -c "sudo su - altschool -c 'sshpass -p '123456' ssh-copy-id -o StrictHostKeyChecking=no altschool@192.168.56.35'"
 vagrant ssh master -c "echo 'altschool ALL=(ALL) NOPASSWD: /bin/* /*' | sudo tee -a /etc/sudoers"
 vagrant ssh master -c "sudo chown vagrant:vagrant /var/www/html/index.html"
 vagrant ssh master -c "sudo sed -i 's/Apache2 Default Page/Apache2 Default Page on Slave Node/' /var/www/html/index.html"
 vagrant ssh master -c "sudo systemctl restart apache2"
 vagrant ssh slave -c "sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config"
 vagrant ssh slave -c "sudo sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config"
 vagrant ssh slave -c "sudo systemctl restart sshd"
 vagrant ssh master -c "sudo su - altschool -c 'ssh altschool@192.168.56.35'"
}
setupmaster

function securemysql() {
 # Start the server if it is not running
 vagrant ssh master -c "sudo systemctl start mysql"
 # Assign a password for the initial MySQL root account
 vagrant ssh master -c "sudo mysql -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY 'AltSchool@2';\""
 # Remove anonymous users
 vagrant ssh master -c "sudo mysql -e \"DELETE FROM mysql.user WHERE User='';\""
 # Disallow root login remotely
 vagrant ssh master -c "sudo mysql -e \"DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');\""
 # Remove test database and access to it
 vagrant ssh master -c "sudo mysql -e \"DROP DATABASE IF EXISTS test;\""
 vagrant ssh master -c "sudo mysql -e \"DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';\""
 # Reload privilege tables now
 vagrant ssh master -c "sudo mysql -e \"FLUSH PRIVILEGES;\""
}
securemysql



function restartapache() {
 vagrant ssh loadbalancer -c "sudo systemctl restart apache2"
}
restartapache
