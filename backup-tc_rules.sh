#!/bin/bash
set -x

# Configuration
NODES_FILE="nodes_ips.txt"
LATENCY_FILE="latencyFile.csv"
INTERFACE="enp3s0"  # Verify interface name
VM_IP="$1"           # Pass VM IP as argument

# Build hostname-to-IP mapping
declare -A HOST_TO_IP
while read -r host ip; do
    HOST_TO_IP["$host"]="$ip"
done < "$NODES_FILE"

# Clear existing rules
sudo tc qdisc del dev $INTERFACE root 2>/dev/null
sudo iptables -t mangle -F

#sudo tc qdisc replace dev enp3s0 root handle 1: htb
#if sudo tc qdisc show dev $INTERFACE | grep -q "qdisc"; then
#    sudo tc qdisc del dev $INTERFACE root
#fi

# Create root hierarchy
sudo tc qdisc add dev $INTERFACE root handle 1: htb

# Process latency rules
while IFS=, read -r src_host dst_host latency; do
    [[ "$src_host" == "source" ]] && continue
    
    src_ip="${HOST_TO_IP[$src_host]}"
    dst_ip="${HOST_TO_IP[$dst_host]}"
    
    # Apply rules ONLY if VM is source or destination
    if [[ "$dst_ip" == "$VM_IP" ]]; then
       # class_id=$(awk -F. '{print $4}' <<< "$dst_ip")
#        class_id=$(( (src_octet << 8) + dst_octet ))
	src_octet=$(awk -F. '{print $4}' <<< "$src_ip")  # Extract 4th octet of source IP
        class_id=$(( src_octet ))                        # Use source IP octet for incoming traffic
        
        sudo tc class add dev $INTERFACE parent 1: classid 1:$class_id htb rate 1000mbit
        sudo tc qdisc add dev $INTERFACE parent 1:$class_id netem delay ${latency}ms
        sudo iptables -t mangle -A PREROUTING -i $INTERFACE -d $src_ip -s $dst_ip -j MARK --set-mark $class_id
        sudo tc filter add dev $INTERFACE parent 1: protocol ip handle $class_id fw flowid 1:$class_id
    
    elif [[ "$src_ip" == "$VM_IP" ]]; then
        
        class_id=$(awk -F. '{print $4}' <<< "$dst_ip")

        sudo tc class add dev $INTERFACE parent 1: classid 1:$class_id htb rate 1000mbit
        sudo tc qdisc add dev $INTERFACE parent 1:$class_id netem delay ${latency}ms
        sudo iptables -t mangle -A PREROUTING -i $INTERFACE -s $src_ip -d $dst_ip -j MARK --set-mark $class_id
        sudo tc filter add dev $INTERFACE parent 1: protocol ip handle $class_id fw flowid 1:$class_id
    fi
done < <(tail -n +2 "$LATENCY_FILE")
