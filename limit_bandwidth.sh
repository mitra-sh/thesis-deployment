USERNAME=" "
PASSWORD=" "
VM_LIST=("192.168.122.169" "192.168.122.26" "192.168.122.210" "192.168.122.233" "192.168.122.71" "192.168.122.162" "192.168.122.9" "192.168.122.136" "192.168.122.174" "192.168.122.226" "192.168.122.193" "192.168.122.238" "192.168.122.198" "192.168.122.157" "192.168.122.211" "192.168.122.137" "192.168.122.88" "192.168.122.28" "192.168.122.244" "192.168.122.4")

FILES=("/home/as00750/storm-net/edgeDeviceBandwidthInfo.csv" "/home/as00750/storm-net/bandwidth_rules.sh")  # Files to copy

copy_files_to_vm() {
    local vm=$1
    /usr/bin/expect << EOF
    set timeout 2000
    spawn /usr/bin/scp -o StrictHostKeyChecking=no \\
        "/home/as00750/storm-net/bandwidth_rules.sh" \\
	"/home/as00750/storm-net/edgeDeviceBandwidthInfo.csv" \\
	"/home/as00750/storm-net/latencyFile.csv" \\
	"/home/as00750/storm-net/nodes_ips.txt" \\
        ${USERNAME}@${vm}:/home/as00750/
    expect "password:"
    send "${PASSWORD}\r"
    expect eof
EOF
}

# Function to run commands on VM using expect
run_commands_on_vm() {
    local vm=$1
    /usr/bin/expect << EOF
    set timeout 200
    spawn ssh ${USERNAME}@${vm}
    expect "password:"
    send "${PASSWORD}\r"
    
    # Set permissions and run script
    expect "$ "
    send "sudo /home/as00750/bandwidth_rules.sh ${vm}\r"
  # Handle sudo password prompt

    expect {
        "password for ${USERNAME}:" {
            send "${PASSWORD}\r"
            exp_continue
        }
        "$ " {
            send "exit\r"
        }
    }
    expect eof
EOF
}

# Main execution loop
for vm in "${VM_LIST[@]}"; do
    # First copy files
    copy_files_to_vm "${vm}" 
    # Then run commands
    run_commands_on_vm "${vm}"
done
