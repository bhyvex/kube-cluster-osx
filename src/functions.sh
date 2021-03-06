#!/bin/bash

# shared functions library

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )


function pause(){
    read -p "$*"
}


function check_iso_offline_setting() {
# check if offline setting is present in setting files

# master
check=$(cat ~/kube-cluster/settings/k8smaster-01.toml | grep "offline" )
if [[ "${check}" = "" ]]
then
    echo '   offline = "true"' >> ~/kube-cluster/settings/k8smaster-01.toml
fi

# node 1
check=$(cat ~/kube-cluster/settings/k8snode-01.toml | grep "offline" )
if [[ "${check}" = "" ]]
then
    echo '   offline = "true"' >> ~/kube-cluster/settings/k8snode-01.toml
fi

# node 2
check=$(cat ~/kube-cluster/settings/k8snode-02.toml | grep "offline" )
if [[ "${check}" = "" ]]
then
    echo '   offline = "true"' >> ~/kube-cluster/settings/k8snode-02.toml
fi

}


function check_corectld_server() {
# check corectld server
#
CHECK_SERVER_STATUS=$(~/bin/corectld status 2>&1 | grep "Uptime:")
if [[ "$CHECK_SERVER_STATUS" == "" ]]; then
    open -a /Applications/corectl.app
fi

if [[ "$CHECK_SERVER_STATUS" == "" ]]; then
    sleep 3
fi
}


function check_internet_from_vm(){
#
status=$(~/bin/corectl ssh k8smaster-01 "curl -s -I https://coreos.com 2>/dev/null | head -n 1 | cut -d' ' -f2")

if [[ $(echo "${status//[$'\t\r\n ']}") = "200" ]]; then
    echo "Yes, internet is available ..."
else
    echo "There is no internet access from the k8smaster-01 VM !!!"
    echo "This also means that could be the same issue on the nodes as well."
    echo " "
    echo "Please check you Mac's firewall, network setup, stop dnsmasq (if you have installed such)"
    echo "and try to fix the problem !!! "
    echo " "
    echo "k8smaster-01 and node VMs are still running, so you can troubleshoot the network problem "
    echo "and when you done fixing it, just 'Halt' and 'Up' via menu and the installation will continue ... "
    echo " "
    # create file 'unfinished_setup' so on next boot fresh install gets triggered again !!!
    touch ~/kube-cluster/logs/unfinished_setup > /dev/null 2>&1
    pause 'Press [Enter] key to abort installation ...'
    exit 1
fi
}


function sshkey(){
# add ssh key to *.toml files
echo " "
echo "Reading ssh key from $HOME/.ssh/id_rsa.pub  "
file="$HOME/.ssh/id_rsa.pub"

while [ ! -f "$file" ]
do
    echo " "
    echo "$file not found."
    echo "please run 'ssh-keygen -t rsa' before you continue !!!"
    pause 'Press [Enter] key to continue...'
done

echo " "
echo "$file found, updating configuration files ..."
echo "   sshkey = '$(cat $HOME/.ssh/id_rsa.pub)'" >> ~/kube-cluster/settings/k8smaster-01.toml
echo "   sshkey = '$(cat $HOME/.ssh/id_rsa.pub)'" >> ~/kube-cluster/settings/k8snode-01.toml
echo "   sshkey = '$(cat $HOME/.ssh/id_rsa.pub)'" >> ~/kube-cluster/settings/k8snode-02.toml
#
}

function release_channel(){
# Set release channel
LOOP=1
while [ $LOOP -gt 0 ]
do
    VALID_MAIN=0
    echo " "
    echo "Set CoreOS Release Channel:"
    echo " 1)  Alpha (may not always function properly)"
    echo " 2)  Beta "
    echo " 3)  Stable (recommended)"
    echo " "
    echo -n "Select an option: "

    read RESPONSE
    XX=${RESPONSE:=Y}

    if [ $RESPONSE = 1 ]
    then
        VALID_MAIN=1
        /usr/bin/sed -i "" 's/channel = "stable"/channel = "alpha"/g' ~/kube-cluster/settings/*.toml
        /usr/bin/sed -i "" 's/channel = "beta"/channel = "alpha"/g' ~/kube-cluster/settings/*.toml
        channel="Alpha"
        LOOP=0
    fi

    if [ $RESPONSE = 2 ]
    then
        VALID_MAIN=1
        /usr/bin/sed -i "" 's/channel = "stable"/channel = "beta"/g' ~/kube-cluster/settings/*.toml
        /usr/bin/sed -i "" 's/channel = "alpha"/channel = "beta"/g' ~/kube-cluster/settings/*.toml
        channel="Beta"
        LOOP=0
    fi

    if [ $RESPONSE = 3 ]
    then
        VALID_MAIN=1
        /usr/bin/sed -i "" 's/channel = "beta"/channel = "stable"/g' ~/kube-cluster/settings/*.toml
        /usr/bin/sed -i "" 's/channel = "alpha"/channel = "stable"/g' ~/kube-cluster/settings/*.toml
        channel="Stable"
        LOOP=0
    fi

    if [ $VALID_MAIN != 1 ]
    then
        continue
    fi
done
}


create_data_disk() {
# path to the bin folder where we store our binary files
export PATH=${HOME}/kube-cluster/bin:$PATH

# create persistent disks
cd ~/kube-cluster/
echo "  "
echo "Creating 5GB sparse disk (QCow2) for Master ..."
~/bin/qcow-tool create --size=5GiB master-data.img
echo "-"
echo "Created 5GB Data disk for Master"
echo " "
# create file 'unfinished_setup' so on next boot fresh install gets triggered again !!!
touch ~/kube-cluster/logs/unfinished_setup > /dev/null 2>&1
#
echo "Please type Nodes Data disk size in GBs followed by [ENTER]:"
echo -n "[default is 15]: "
read disk_size
if [ -z "$disk_size" ]
then
    echo " "
    echo "Creating 15GB sparse disk (QCow2) for Node1..."
    ~/bin/qcow-tool create --size=15GiB node-01-data.img
    echo "-"
    echo "Created 15GB Data disk for Node1"
    echo " "
    echo "Creating 15GB sparse disk (QCow2) for Node2..."
    ~/bin/qcow-tool create --size=15GiB node-02-data.img
    echo "-"
    echo "Created 15GB Data disk for Node2"
else
    echo " "
    echo "Creating "$disk_size"GB sparse disk (QCow2) for Node1..."
    ~/bin/qcow-tool create --size="$disk_size"GiB node-01-data.img
    echo "-"
    echo "Created "$disk_size"GB Data disk for Node1"
    echo " "
    echo "Creating "$disk_size"GB sparse disk (QCow2) for Node2..."
    ~/bin/qcow-tool create --size="$disk_size"GiB node-02-data.img
    echo "-"
    echo "Created "$disk_size"GB Data disk for Node2"
fi

}

change_nodes_ram() {
echo " "
echo " "
echo "Please type Nodes RAM size in GBs followed by [ENTER]:"
echo -n "[default is 2]: "
read ram_size
if [ -z "$ram_size" ]
then
    ram_size=2
    echo "Changing Nodes RAM to "$ram_size"GB..."
    ((new_ram_size=$ram_size*1024))
    /usr/bin/sed -i "" 's/\(memory = \)\(.*\)/\1'$new_ram_size'/g' ~/kube-cluster/settings/k8snode-01.toml
    /usr/bin/sed -i "" 's/\(memory = \)\(.*\)/\1'$new_ram_size'/g' ~/kube-cluster/settings/k8snode-02.toml
    echo " "
else
    echo "Changing Nodes RAM to "$ram_size"GB..."
    ((new_ram_size=$ram_size*1024))
    /usr/bin/sed -i "" 's/\(memory = \)\(.*\)/\1'$new_ram_size'/g' ~/kube-cluster/settings/k8snode-01.toml
    /usr/bin/sed -i "" 's/\(memory = \)\(.*\)/\1'$new_ram_size'/g' ~/kube-cluster/settings/k8snode-02.toml
    echo " "
fi

}


function start_vms() {

# Start VMs
cd ~/kube-cluster
echo " "
echo "Starting k8smaster-01 VM ..."
#
~/bin/corectl load settings/k8smaster-01.toml 2>&1 | tee ~/kube-cluster/logs/master_vm_up.log
CHECK_VM_STATUS=$(cat ~/kube-cluster/logs/master_vm_up.log | grep "started")
#
if [[ "$CHECK_VM_STATUS" == "" ]]; then
    echo " "
    echo "Master VM has not booted, please check '~/kube-cluster/logs/master_vm_up.log' and report the problem !!! "
    echo " "
    # create file 'unfinished_setup' so on next boot fresh install gets triggered again !!!
    touch ~/kube-cluster/logs/unfinished_setup > /dev/null 2>&1
    pause 'Press [Enter] key to continue...'
    exit 0
else
    echo "Master VM successfully started !!!" >> ~/kube-cluster/logs/master_vm_up.log
fi

# save master VM's IP
~/bin/corectl q -i k8smaster-01 | tr -d "\n" > ~/kube-cluster/.env/master_ip_address
# get master VM's IP
master_vm_ip=$(~/bin/corectl q -i k8smaster-01)
#
sleep 2
#
echo " "
echo "Starting k8snode-01 VM ..."
#
~/bin/corectl load settings/k8snode-01.toml 2>&1 | tee ~/kube-cluster/logs/node1_vm_up.log
CHECK_VM_STATUS=$(cat ~/kube-cluster/logs/node1_vm_up.log | grep "started")
#
if [[ "$CHECK_VM_STATUS" == "" ]]; then
    echo " "
    echo "Node1 VM has not booted, please check '~/kube-cluster/logs/node1_vm_up.log' and report the problem !!! "
    echo " "
    # create file 'unfinished_setup' so on next boot fresh install gets triggered again !!!
    touch ~/kube-cluster/logs/unfinished_setup > /dev/null 2>&1
    pause 'Press [Enter] key to continue...'
    exit 0
else
    echo "Node1 VM successfully started !!!" >> ~/kube-cluster/logs/node1_vm_up.log
fi
echo " "
# save node1 VM's IP
~/bin/corectl q -i k8snode-01 | tr -d "\n" > ~/kube-cluster/.env/node1_ip_address
# get node1 VM's IP
node1_vm_ip=$(~/bin/corectl q -i k8snode-01)
#
#
echo "Starting k8snode-02 VM ..."
#
~/bin/corectl load settings/k8snode-02.toml 2>&1 | tee ~/kube-cluster/logs/node2_vm_up.log
CHECK_VM_STATUS=$(cat ~/kube-cluster/logs/node2_vm_up.log | grep "started")
#
if [[ "$CHECK_VM_STATUS" == "" ]]; then
    echo " "
    echo "Node2 VM has not booted, please check '~/kube-cluster/logs/node2_vm_up.log' and report the problem !!! "
    echo " "
    # create file 'unfinished_setup' so on next boot fresh install gets triggered again !!!
    touch ~/kube-cluster/logs/unfinished_setup > /dev/null 2>&1
    pause 'Press [Enter] key to continue...'
    exit 0
else
    echo "Node2 VM successfully started !!!" >> ~/kube-cluster/logs/node2_vm_up.log
fi
echo " "
# save node2 VM's IP
~/bin/corectl q -i k8snode-02 | tr -d "\n" > ~/kube-cluster/.env/node2_ip_address
# get node2 VM's IP
node2_vm_ip=$(~/bin/corectl q -i k8snode-02)

}


function stop_vms(){
echo "Stopping VMs ..."
echo " "
echo "Stopping k8smaster-01 VM ..."
# send halt to VM
~/bin/corectl halt k8smaster-01
sleep 1
#
echo " "
echo "Stopping k8snode-01 VM ..."
# send halt to VM
~/bin/corectl halt k8snode-01
sleep 1
#
echo " "
echo "Stopping k8snode-02 VM ..."
# send halt to VM
~/bin/corectl halt k8snode-02
sleep 1

}


function download_osx_clients() {
# download fleetctl file
FLEETCTL_VERSION=$(~/bin/corectl ssh k8smaster-01 'fleetctl --version' | awk '{print $3}' | tr -d '\r')
FILE=fleetctl
if [ ! -f ~/kube-cluster/bin/$FILE ]; then
    cd ~/kube-cluster/bin
    echo "Downloading fleetctl v$FLEETCTL_VERSION for macOS"
    curl -L -o fleet.zip "https://github.com/coreos/fleet/releases/download/v$FLEETCTL_VERSION/fleet-v$FLEETCTL_VERSION-darwin-amd64.zip"
    unzip -j -o "fleet.zip" "fleet-v$FLEETCTL_VERSION-darwin-amd64/fleetctl" > /dev/null 2>&1
    rm -f fleet.zip
else
    # we check the version of the binary
    INSTALLED_VERSION=$(~/kube-cluster/bin/$FILE --version | awk '{print $3}' | tr -d '\r')
    MATCH=$(echo "${INSTALLED_VERSION}" | grep -c "${FLEETCTL_VERSION}")
    if [ $MATCH -eq 0 ]; then
        # the version is different
        cd ~/kube-cluster/bin
        echo "Downloading fleetctl v$FLEETCTL_VERSION for macOS"
        curl -L -o fleet.zip "https://github.com/coreos/fleet/releases/download/v$FLEETCTL_VERSION/fleet-v$FLEETCTL_VERSION-darwin-amd64.zip"
        unzip -j -o "fleet.zip" "fleet-v$FLEETCTL_VERSION-darwin-amd64/fleetctl" > /dev/null 2>&1
        rm -f fleet.zip
    else
        echo " "
        echo "fleetctl is up to date ..."
        echo " "
    fi
fi

# get lastest macOS helmc cli version
cd ~/kube-cluster/bin
echo "Downloading latest version of helmc cli for macOS"
curl -o helmc https://storage.googleapis.com/helm-classic/helmc-latest-darwin-amd64
chmod +x helmc
echo " "
echo "Installed latest helmc cli to ~/kube-cluster/bin ..."
#

# get lastest macOS deis cli version
cd ~/kube-cluster/bin
echo "Downloading latest version of Workflow deis cli for macOS"
curl -o deis https://storage.googleapis.com/workflow-cli/deis-latest-darwin-amd64
chmod +x deis
echo " "
echo "Installed latest deis cli to ~/kube-cluster/bin ..."
#

}


function download_k8s_files() {
#
cd ~/kube-cluster/tmp

# get latest stable k8s version
function get_latest_version_number {
    local -r latest_url="https://storage.googleapis.com/kubernetes-release/release/stable.txt"
    curl -Ss ${latest_url}
}
K8S_VERSION=$(get_latest_version_number)

# we check the version of installed k8s cluster
INSTALLED_VERSION=$(~/kube-cluster/bin/kubectl version | grep "Server Version:" | awk '{print $5}' | awk -v FS='(:"|",)' '{print $2}')
MATCH=$(echo "${INSTALLED_VERSION}" | grep -c "${K8S_VERSION}")
if [ $MATCH -ne 0 ]; then
    echo " "
    echo "You have already the latest stable ${K8S_VERSION} of Kubernetes installed !!!"
    pause 'Press [Enter] key to continue...'
    exit 1
fi

k8s_upgrade=1

# clean up tmp folder
rm -rf ~/kube-cluster/tmp/*

# download latest version of kubectl for macOS
cd ~/kube-cluster/tmp
echo "Downloading kubectl $K8S_VERSION for macOS"
curl -k -L https://storage.googleapis.com/kubernetes-release/release/$K8S_VERSION/bin/darwin/amd64/kubectl >  ~/kube-cluster/kube/kubectl
chmod 755 ~/kube-cluster/kube/kubectl
echo "kubectl was copied to ~/kube-cluster/kube"
echo " "

# clean up tmp folder
rm -rf ~/kube-cluster/tmp/*

# download latest version of k8s for CoreOS
echo "Downloading Kubernetes $K8S_VERSION"
bins=( kubectl kubelet kube-proxy kube-apiserver kube-scheduler kube-controller-manager )
for b in "${bins[@]}"; do
    curl -k -L https://storage.googleapis.com/kubernetes-release/release/$K8S_VERSION/bin/linux/amd64/$b > ~/kube-cluster/tmp/$b
done
#
chmod 755 ~/kube-cluster/tmp/*
#
curl -L https://storage.googleapis.com/kubernetes-release/easy-rsa/easy-rsa.tar.gz > ~/kube-cluster/tmp/easy-rsa.tar.gz
#
tar czvf kube.tgz *
cp -f kube.tgz ~/kube-cluster/kube/
# clean up tmp folder
rm -rf ~/kube-cluster/tmp/*
echo " "

# install k8s files
install_k8s_files

}


function download_k8s_files_version() {
#
cd ~/kube-cluster/tmp

# ask for k8s version
echo "You can install a particular version of Kubernetes you migh want to test..."
echo " "
echo "Bear in mind if the version you want is lower than the currently installed, "
echo "Kubernetes cluster migth not work, so you will need to destroy the cluster first "
echo "and boot VM again !!! "
echo " "
echo "Please type Kubernetes version you want to be installed e.g. v1.3.2 or v1.4.0-alpha.2"
echo "followed by [ENTER] to continue or press CMD + W to exit:"
read K8S_VERSION

url=https://github.com/kubernetes/kubernetes/releases/download/$K8S_VERSION/kubernetes.tar.gz

if curl --output /dev/null --silent --head --fail "$url"; then
    echo "URL exists: $url" > /dev/null
else
    echo " "
    echo "There is no such Kubernetes version to download !!!"
    echo "List of available Kubernetes versions:"
    curl -s https://api.github.com/repos/kubernetes/kubernetes/releases | grep "tag_name" | awk '{print $2}' | sed -e 's/"\(.*\)"./\1/' | sort -n
    pause 'Press [Enter] key to continue...'
    exit 1
fi

# we check the version of installed k8s cluster
INSTALLED_VERSION=$(~/kube-cluster/bin/kubectl version | grep "Server Version:" | awk '{print $5}' | awk -v FS='(:"|",)' '{print $2}')
MATCH=$(echo "${INSTALLED_VERSION}" | grep -c "${K8S_VERSION}")
if [ $MATCH -ne 0 ]; then
    echo " "
    echo "You have already the ${K8S_VERSION} of Kubernetes installed !!!"
    pause 'Press [Enter] key to continue...'
    exit 1
fi

k8s_upgrade=1

# clean up tmp folder
rm -rf ~/kube-cluster/tmp/*

# download required version of Kubernetes
cd ~/kube-cluster/tmp
echo " "
echo "Downloading Kubernetes $K8S_VERSION tar.gz from github ..."
curl -k -L https://github.com/kubernetes/kubernetes/releases/download/$K8S_VERSION/kubernetes.tar.gz >  kubernetes.tar.gz
#
# extracting Kubernetes files
echo "Extracting Kubernetes $K8S_VERSION files ..."
tar xvf  kubernetes.tar.gz --strip=4 kubernetes/platforms/darwin/amd64/kubectl
mv -f kubectl ~/kube-cluster/kube
chmod 755 ~/kube-cluster/kube/kubectl
#
tar xvf kubernetes.tar.gz --strip=2 kubernetes/server/kubernetes-server-linux-amd64.tar.gz
bins=( kubectl kubelet kube-proxy kube-apiserver kube-scheduler kube-controller-manager )
for b in "${bins[@]}"; do
    tar xvf kubernetes-server-linux-amd64.tar.gz -C ~/kube-cluster/tmp --strip=3 kubernetes/server/bin/$b
done
rm -f kubernetes.tar.gz
rm -f kubernetes-server-linux-amd64.tar.gz
#
curl -L https://storage.googleapis.com/kubernetes-release/easy-rsa/easy-rsa.tar.gz > easy-rsa.tar.gz
#
tar czvf kube.tgz *
mv -f kube.tgz ~/kube-cluster/kube/
# clean up tmp folder
rm -rf ~/kube-cluster/tmp/*
echo " "

# install k8s files
install_k8s_files

}


function deploy_fleet_units() {
# deploy fleet units from ~/kube-cluster/fleet
cd ~/kube-cluster/fleet
echo "Starting all fleet units in ~/kube-cluster/fleet:"
fleetctl start fleet-ui.service
fleetctl start kube-apiserver.service
fleetctl start kube-controller-manager.service
fleetctl start kube-scheduler.service
fleetctl start kube-kubelet.service
fleetctl start kube-proxy.service
echo " "
echo "fleetctl list-units:"
fleetctl list-units
echo " "

}


function install_k8s_files {
# get App's Resources folder
res_folder=$(cat ~/kube-cluster/.env/resouces_path)

# get master VM's IP
master_vm_ip=$(~/bin/corectl q -i k8smaster-01)

# check if file ~/kube-cluster/kube/kube.tgz exists
if [ ! -f ~/kube-cluster/kube/kube.tgz ]
then
    # copy k8s files
    cp -f "${res_folder}"/k8s/kubectl ~/kube-cluster/kube
    chmod +x ~/kube-cluster/kube/kubectl
    # linux binaries tar file
    cp -f "${res_folder}"/k8s/kube.tgz ~/kube-cluster/kube
fi

# install k8s files on to VMs
echo " "
echo "Installing Kubernetes files on to VMs..."
echo " "
cd ~/kube-cluster/kube
echo "Installing into k8smaster-01..."
~/bin/corectl scp kube.tgz k8smaster-01:/home/core/
echo "Files copied to VM..."
echo "Installing now ..."
~/bin/corectl ssh k8smaster-01 'sudo /usr/bin/mkdir -p /data/opt/bin && sudo tar xzf /home/core/kube.tgz -C /data/opt/bin && sudo chmod 755 /data/opt/bin/*'
~/bin/corectl ssh k8smaster-01 'sudo /usr/bin/mkdir -p /opt/tmp && sudo mv /data/opt/bin/easy-rsa.tar.gz /opt/tmp'
echo "Done with k8smaster-01 "
echo " "
#
echo "Installing into k8snode-01..."
~/bin/corectl scp kube.tgz k8snode-01:/home/core/
echo "Files copied to VM..."
echo "Installing now ..."
~/bin/corectl ssh k8snode-01 'sudo /usr/bin/mkdir -p /data/opt/bin && sudo tar xzf /home/core/kube.tgz -C /data/opt/bin && sudo chmod 755 /data/opt/bin/*'
~/bin/corectl ssh k8snode-01 'sudo /usr/bin/mkdir -p /opt/tmp && sudo mv /data/opt/bin/easy-rsa.tar.gz /opt/tmp'
echo "Done with k8snode-01 "
echo " "
#
echo "Installing into k8snode-02..."
~/bin/corectl scp kube.tgz k8snode-02:/home/core/
echo "Files copied to VM..."
echo "Installing now ..."
~/bin/corectl ssh k8snode-02 'sudo /usr/bin/mkdir -p /data/opt/bin && sudo tar xzf /home/core/kube.tgz -C /data/opt/bin && sudo chmod 755 /data/opt/bin/*'
~/bin/corectl ssh k8snode-02 'sudo /usr/bin/mkdir -p /opt/tmp && sudo mv /data/opt/bin/easy-rsa.tar.gz /opt/tmp'
echo "Done with k8snode-02 "
echo " "
}


function install_k8s_add_ons {
echo " "
echo "Creating kube-system namespace ..."
~/kube-cluster/bin/kubectl create -f ~/kube-cluster/kubernetes/kube-system-ns.yaml > /dev/null 2>&1
#
#/usr/bin/sed -i "" "s/_MASTER_IP_/$1/" ~/kube-cluster/kubernetes/skydns-rc.yaml
echo " "
echo "Installing SkyDNS ..."
~/kube-cluster/bin/kubectl create -f ~/kube-cluster/kubernetes/skydns-rc.yaml
~/kube-cluster/bin/kubectl create -f ~/kube-cluster/kubernetes/skydns-svc.yaml
#
echo " "
echo "Installing Kubernetes UI ..."
~/kube-cluster/bin/kubectl create -f ~/kube-cluster/kubernetes/dashboard-controller.yaml
~/kube-cluster/bin/kubectl create -f ~/kube-cluster/kubernetes/dashboard-service.yaml
#
echo " "
echo "Installing Kubedash ..."
~/kube-cluster/bin/kubectl create -f ~/kube-cluster/kubernetes/kubedash.yaml
sleep 1
# clean up kubernetes folder
rm -f ~/kube-cluster/kubernetes/kube-system-ns.yaml
rm -f ~/kube-cluster/kubernetes/skydns-rc.yaml
rm -f ~/kube-cluster/kubernetes/skydns-svc.yaml
rm -f ~/kube-cluster/kubernetes/dashboard-controller.yaml
rm -f ~/kube-cluster/kubernetes/dashboard-service.yaml
rm -f ~/kube-cluster/kubernetes/kubedash.yaml
echo " "
}


function clean_up_after_vm {
sleep 1

# get App's Resources folder
res_folder=$(cat ~/kube-cluster/.env/resouces_path)

# path to the bin folder where we store our binary files
export PATH=${HOME}/kube-cluster/bin:$PATH

# get App's Resources folder
res_folder=$(cat ~/kube-cluster/.env/resouces_path)

# send halt to VMs
~/bin/corectl halt k8snode-01
sleep 1
~/bin/corectl halt k8snode-02
sleep 1
~/bin/corectl halt k8smaster-01

# kill all other scripts
pkill -f [K]ube-Solo.app/Contents/Resources/fetch_latest_iso.command
pkill -f [K]ube-Solo.app/Contents/Resources/update_k8s.command
pkill -f [K]ube-Solo.app/Contents/Resources/update_osx_clients_files.command
pkill -f [K]ube-Solo.app/Contents/Resources/change_release_channel.command

}

