#!/bin/bash

# Get the IP address of the VM
VM_IP=$(hostname -I | awk '{print $1}')

# Export the IP address as an environment variable
export VM_IP

# Start the Storm supervisor
storm supervisor
