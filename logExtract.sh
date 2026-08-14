#!/bin/bash

# Define the user and password
USER=" "
PASSWORD=" "

# Create a directory to store logs
mkdir -p supervisor_logs

# Read node IP mappings into an associative array
declare -A NODE_IPS
while read -r node ip; do
    NODE_IPS[$node]=$ip
done < nodes_ips.txt

# Debug: Print node IP mappings
echo "Node to IP mappings:"
for node in "${!NODE_IPS[@]}"; do
    echo "$node -> ${NODE_IPS[$node]}"
done

# Step 1: List supervisor services
echo "Listing all supervisor services..."
service_names=$(docker service ls --format "{{.Name}}" | grep "^storm_supervisor-")

if [ -z "$service_names" ]; then
    echo "No services matching storm_supervisor-* found. Exiting."
    exit 1
fi

echo "Detected supervisor services:"
echo "$service_names"

# Step 2: List all running containers for the detected services
echo "Collecting service tasks..."
nodes_containers=""
for svc in $service_names; do
    echo "Fetching tasks for service: $svc"
    tmp=$(docker service ps "$svc" --no-trunc --format "{{.Name}} {{.Node}} {{.ID}}")
    nodes_containers="$nodes_containers"$'\n'"$tmp"
done

# Strip empty lines
nodes_containers=$(echo "$nodes_containers" | sed '/^\s*$/d')

if [ -z "$nodes_containers" ]; then
    echo "No tasks found for services. Exiting."
    exit 1
fi

echo "Service, Node, and Container IDs:"
echo "$nodes_containers"

# Step 3: Loop through each node and container
IFS=$'\n'
for entry in $nodes_containers; do
    service_name=$(echo $entry | awk '{split($1, n, "."); print n[1]}')  # Extract service name
    node=$(echo $entry | awk '{print $2}')                             # Extract node name
    partial_id=$(echo $entry | awk '{print $3}')                       # Extract container task ID
    ip=${NODE_IPS[$node]}

    if [ -z "$ip" ]; then
        echo "IP address for node $node not found. Skipping..."
        continue
    fi

    echo "Processing container $partial_id on service $service_name, node $node ($ip)..."

    # Fetch full container name
    full_container_name=$(sshpass -p $PASSWORD ssh -o StrictHostKeyChecking=no $USER@$ip \
        "sudo docker ps --filter 'name=$service_name' --format '{{.Names}}' | grep '$partial_id'")

    if [ -z "$full_container_name" ]; then
        echo "No running container found for task ID: $partial_id on node $node ($ip). Skipping..."
        continue
    fi

    echo "Full container name: $full_container_name"

    # Copy logs from the container
    sshpass -p $PASSWORD ssh -o StrictHostKeyChecking=no $USER@$ip \
        "sudo mkdir -p /tmp/$partial_id-logs && \
        sudo docker cp $full_container_name:/apache-storm-2.7.0/logs /tmp/$partial_id-logs"

    # Copy logs back to the local system
    local_log_dir="supervisor_logs/$service_name/$node-logs"
    mkdir -p "$local_log_dir"

    echo "Copying logs from node $node ($ip)..."
    sshpass -p $PASSWORD scp -o StrictHostKeyChecking=no -r $USER@$ip:/tmp/$partial_id-logs "$local_log_dir/"

    # Clean up logs on remote node
    sshpass -p $PASSWORD ssh -o StrictHostKeyChecking=no $USER@$ip "sudo rm -rf /tmp/$partial_id-logs"

    echo "Finished processing logs for container $partial_id on node $node ($ip)"
done

echo "All logs have been successfully extracted to the supervisor_logs directory."
