#!/bin/bash
#
# Automatically deploy a Cuckoo sandbox

function downloadAgent() {
	# Agent.ova is a Windows7 (x86) virtual machine and used to be an Cuckoo agent
	url="https://drive.google.com/u/0/uc?id=1uGxNwvSuSIhokeuX9N61D8VtyFDoK0-2&export=download"
	# Download from google drive (Manually download if not working)
	gdown --speed=50MB $url -O ~/Downloads/Agent.ova
}

function installDependencies() {
	# Update system dependencies
	sudo apt-get update -y && sudo apt-get upgrade -y

	# Install basic system dependencies
	# https://askubuntu.com/questions/339790/how-can-i-prevent-apt-get-aptitude-from-showing-dialogs-during-installation/340846
	echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
	echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
	sudo apt-get install -y virtualbox vim curl net-tools htop python python-pip python-dev libffi-dev libssl-dev python-virtualenv python-setuptools python-magic python-libvirt ssdeep libjpeg-dev zlib1g-dev swig mongodb postgresql libpq-dev build-essential git libpcre3 libpcre3-dev libpcre++-dev libfuzzy-dev automake make libtool gcc tcpdump dh-autoreconf flex bison libjansson-dev libmagic-dev libyaml-dev libpython2.7-dev tcpdump apparmor-utils iptables-persistent

	sudo pip install --upgrade pip
	# Install Python dependencies
	sudo pip install -U gdown==3.10.0 sqlalchemy==1.3.3 pefile==2019.4.18 pyrsistent==0.17.0 dpkt==1.8.7 jinja2==2.9.6 pymongo==3.0.3 bottle yara-python==3.6.3 requests==2.13.0 python-dateutil==2.4.2 chardet==2.3.0 setuptools psycopg2 pycrypto pydeep distorm3 cuckoo==2.0.7 weasyprint==0.36 m2crypto openpyxl ujson pycrypto pytz pyOpenSSL
	# Reinstall werkzeug
	sudo pip uninstall --yes werkzeug && sudo pip install werkzeug==0.16.1

	# Install pySSDeep&yara&volatility
	git clone https://github.com/bunzen/pySSDeep.git ~/Downloads/pySSDeep && cd ~/Downloads/pySSDeep && sudo python setup.py build && sudo python setup.py install && cd ~
	wget https://github.com/VirusTotal/yara/archive/v3.7.1.tar.gz -O ~/Downloads/v3.7.1.tar.gz && tar -xzvf ~/Downloads/v3.7.1.tar.gz -C ~/Downloads && cd ~/Downloads/yara-3.7.1 && sudo ./bootstrap.sh && sudo ./configure --with-crypto --enable-cuckoo --enable-magic && sudo make && sudo make install && cd ~
	git clone https://github.com/volatilityfoundation/volatility.git ~/Downloads/volatility && cd ~/Downloads/volatility && sudo python ./setup.py build && sudo python ./setup.py install && cd ~
}

function configureVirtualbox() {
	# Create hostonly ethernet adapter
	vboxmanage hostonlyif create && vboxmanage hostonlyif ipconfig vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0

	# Change the default storage directory and permission
	sudo mkdir /data && sudo mkdir /data/VirtualBoxVms && sudo chmod 777 /data/VirtualBoxVms
	vboxmanage setproperty machinefolder /data/VirtualBoxVms

	# Import Agent.ova and take a snapshot
	vboxmanage import $1 && vboxmanage modifyvm "Agent" --name "cuckoo1" && vboxmanage startvm "cuckoo1" --type headless
	sleep 3m
	vboxmanage snapshot "cuckoo1" take "snap1" && vboxmanage controlvm "cuckoo1" poweroff && vboxmanage snapshot "cuckoo1" restorecurrent
}

function configureNetwork() {
	# Configure tcpdump
	sudo aa-disable /usr/sbin/tcpdump && sudo setcap cap_net_raw,cap_net_admin=eip /usr/sbin/tcpdump

	# Open Ip forwarding
	sudo iptables -A FORWARD -i vboxnet0 -s 192.168.56.0/24 -m conntrack --ctstate NEW -j ACCEPT && sudo iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT && sudo iptables -A POSTROUTING -t nat -j MASQUERADE
	sudo sed -i "s/#net.ipv4.ip_forward=/net.ipv4.ip_forward=/g" /etc/sysctl.conf

	# Configuration persistence
	sudo sysctl -p /etc/sysctl.conf && sudo netfilter-persistent save

	# Configure system DNS
	sudo sed -i "s/127.0.0.53/8.8.8.8/g" /etc/resolv.conf

}

function configCuckoo() {
	# initialize cuckoo
	sudo service mongodb start && cuckoo && cuckoo community

	# Add Agent to cuckoo
	cuckoo machine --delete cuckoo1 && cuckoo machine --add cuckoo1 192.168.56.5 --platform windows --snapshot snap1

	# open MongoDB and VirusTotal
	sed "45d" ~/.cuckoo/conf/reporting.conf > ~/.cuckoo/conf/tmp.conf && sed -i "/mongodb]/a\enabled = yes" ~/.cuckoo/conf/tmp.conf && rm -rf ~/.cuckoo/conf/reporting.conf && mv ~/.cuckoo/conf/tmp.conf ~/.cuckoo/conf/reporting.conf
	sed "148d" ~/.cuckoo/conf/processing.conf > ~/.cuckoo/conf/tmp.conf && sed -i "/virustotal]/a\enabled = yes" ~/.cuckoo/conf/tmp.conf && rm -rf ~/.cuckoo/conf/processing.conf && mv ~/.cuckoo/conf/tmp.conf ~/.cuckoo/conf/processing.conf
}

echo -e "\033[41;30m-----------------------------------------\033[0m"
echo -e "\033[41;30m Step 1: Install and update dependencies \033[0m"
echo -e "\033[41;30m-----------------------------------------\033[0m"
installDependencies

echo -e "\033[41;30m--------------------------------------------------\033[0m"
echo -e "\033[41;30m Step 2: Download Agent.ova virtual machine file  \033[0m"
echo -e "\033[41;30m--------------------------------------------------\033[0m"
downloadAgent

echo -e "\033[41;30m------------------------------\033[0m"
echo -e "\033[41;30m Step 3: Configure VirtualBox \033[0m"
echo -e "\033[41;30m------------------------------\033[0m"
configureVirtualbox ~/Downloads/Agent.ova

echo -e "\033[41;30m---------------------------\033[0m"
echo -e "\033[41;30m Step 4: Configure Network \033[0m"
echo -e "\033[41;30m---------------------------\033[0m"
configureNetwork

echo -e "\033[41;30m--------------------------\033[0m"
echo -e "\033[41;30m Step 5: Configure Cuckoo \033[0m"
echo -e "\033[41;30m--------------------------\033[0m"
configCuckoo

echo -e "\033[41;30m-----------------------------\033[0m"
echo -e "\033[41;30m Step 6: Run Cuckoo services \033[0m"
echo -e "\033[41;30m-----------------------------\033[0m"
cuckoo &> ~/Desktop/cuckoo.log &
cuckoo web -H 0.0.0.0 -p 8000 &> ~/Desktop/cuckoo_web.log &

echo -e "\033[42;30m-----------------------------------------------\033[0m"
echo -e "\033[42;30m Done! Cuckoo web service running on port 8000 \033[0m"
echo -e "\033[42;30m-----------------------------------------------\033[0m"

#!/bin/bash
#
# Start analysis

function startVM() {
	vboxmanage startvm "cuckoo1" --type headless
}

function startCuckoo() {
	cuckoo
}

echo -e "\033[41;30m------------------------------\033[0m"
echo -e "\033[41;30m Start VM (cuckoo1) \033[0m"
echo -e "\033[41;30m------------------------------\033[0m"
startVM

echo -e "\033[41;30m------------------------------\033[0m"
echo -e "\033[41;30m Start Cuckoo \033[0m"
echo -e "\033[41;30m------------------------------\033[0m"
startCuckoo
