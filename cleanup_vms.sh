#!/bin/bash

echo "Clearing files starting with 'executionTime_'..."
rm -f /home/as00750/executionTime_*

echo "Clearing files starting with 'remainingBW_'..."
rm -f /home/as00750/remainingBW_*

echo "Clearing files starting with 'cpuUsage_'..."
rm -f /home/as00750/cpuUsage_*


echo "Clearing application setting file"
rm -f /home/as00750/applicationSettings*.csv

#sudo docker builder prune -a --force 
#sudo rm -rf /var/log/.log
#sudo rm -rf /var/log/journal/
#sudo docker image prune -f && sudo docker rmi $(sudo docker images -a -q) -f
# Define VM details
USERNAME="as00750"
PASSWORD="ChangeMeNow"
VM_LIST=("192.168.122.169" "192.168.122.26" "192.168.122.210" "192.168.122.233" "192.168.122.71" "192.168.122.162" "192.168.122.9" "192.168.122.136" "192.168.122.174" "192.168.122.226" "192.168.122.193" "192.168.122.238" "192.168.122.198" "192.168.122.157" "192.168.122.211" "192.168.122.137" "192.168.122.88" "192.168.122.28" "192.168.122.244" "192.168.122.4")

# Command to be run on each VM
COMMAND="find ./images/ -mindepth 1 -delete ; \
sudo dmesg -C ; \
sudo docker system prune -f ; \
sudo docker volume prune -f ; \
sudo docker image prune -a -f ; \
sudo docker network prune -f ; \
sudo rm -rf /var/log/.log ; \
sudo docker images -a -q | xargs -r sudo docker rmi -f ; \
sudo docker builder prune -a --force ; \
sudo docker rmi -f $(docker images mitrash/custom-storm -q) || true ; \
sudo rm -f /home/as00750/*.csv ; \
sudo rm -f /home/as00750/*.sh ; \
sudo rm -f /home/as00750/*.txt ; \
sudo tc qdisc del dev enp3s0 root 2>/dev/null || true ; \
sudo tc qdisc del dev enp3s0 ingress 2>/dev/null || true ; \
sudo ip link del ifb0 2>/dev/null || true ; \
sudo rm -rf /var/log/journal/"
#sudo rm -f /home/as00750/*.csv && \
#sudo rm -f /home/as00750/*.sh && \
#sudo rm -f /home/as00750/*.txt && \
#sudo tcdel enp3s0 --all && \
#sudo tcset --device enp3s0 --delete 2>/dev/null || true && \
#sudo rm -rf /var/log/journal/"
#sudo docker builder prune -a --force && \
#sudo docker images -a -q | xargs -r sudo docker rmi -f  && \


# Function to run commands on VM using expect
run_commands_on_vm() {
    local vm=$1
    /usr/bin/expect << EOF
    set timeout -1
    spawn ssh ${USERNAME}@${vm}
    expect "password:"
    send "${PASSWORD}\r"
    expect "$ "
    send "${COMMAND}\r"
    expect "$ "
    send "exit\r"
    expect eof
EOF
}


#echo "All commands executed."
sudo docker builder prune -a --force 
sudo rm -rf /var/log/.log
sudo rm -rf /var/log/journal/
sudo docker rmi -f $(docker images mitrash/custom-storm -q) || true 

# Loop through all VMs and run the commands
for vm in "${VM_LIST[@]}"; do
    echo "Running commands on ${vm}..."
    run_commands_on_vm ${vm}
done

