#!/bin/bash
set -x

echo "Entrypoint is running"

# Print all environment variables
echo "Environment Variables:"
env
# Check if STORM_ROLE is set
if [ -z "$STORM_ROLE" ]; then
  echo "STORM_ROLE is not set. Exiting."
  exit 1
fi



# Perform role-specific actions
if [ "$STORM_ROLE" = "nimbus" ]; then
 	echo "Starting Nimbus..."
   # Check if SUPERVISOR_META_NODE is set


        # Attempt to update supervisor.scheduler.meta in storm.yaml
        echo "Attempting to modify storm.yaml..."
        sed -i "/^supervisor.scheduler.meta:/ {n; s/.*/  nodeName: \"$NODE_HOSTNAME\"/}" /conf/storm.yaml


        # Check the exit status of the sed command
        if [ $? -eq 0 ]; then
          echo "storm.yaml modified successfully."
        else
          echo "Failed to modify storm.yaml."
        fi

        # Display the updated storm.yaml
        echo "Updated storm.yaml content:"
        cat /conf/storm.yaml

  # Start the Nimbus process
  	exec storm nimbus

elif [ "$STORM_ROLE" = "supervisor" ]; then
  	echo "Starting Supervisor..."


	# Check if SUPERVISOR_META_NODE is set
	if [ -n "$NODE_HOSTNAME" ]; then
	  echo "NODE_HOSTNAME is set to: $NODE_HOSTNAME"
	else
	  echo "NODE_HOSTNAME is not set"
	fi

	if [ -z "$NODE_HOSTNAME" ]; then
  		echo "NODE_HOSTNAME is not set. Attempting to set it automatically."
  		NODE_HOSTNAME=$TARGET_VM_NAME
  		export NODE_HOSTNAME
  		echo "NODE_HOSTNAME set to: $TARGET_VM_NAME"
	fi	



        if [ "$NODE_HOSTNAME" = "as00750-02" ]; then
                echo "Configuring this node ($NODE_HOSTNAME) to have 2 worker slots."
      # Remove any existing supervisor.slots.ports lines and re-append the new config
                sed -i '/^supervisor.slots.ports:/,/^- /d' /conf/storm.yaml

                cat <<EOF >> /conf/storm.yaml
supervisor.slots.ports:
        - 6700
        - 6701
        - 6702
#        - 6703
worker.heap.memory.mb: 2048
worker.childopts: "-Xms2048m -Xmx2048m"
topology.worker.max.heap.size.mb: 3072
topology.component.resources.onheap.memory.mb: 1024
supervisor.memory.capacity.mb: 12480
EOF
        else
               echo "Configuring this node ($NODE_HOSTNAME) to have 4 worker slots."
               sed -i '/^supervisor.slots.ports:/,/^- /d' /conf/storm.yaml

               cat <<EOF >> /conf/storm.yaml
supervisor.slots.ports:
        - 6700
worker.heap.memory.mb: 4096
worker.childopts: "-Xms4096m -Xmx4096m"
topology.worker.max.heap.size.mb: 4096
topology.component.resources.onheap.memory.mb: 1024
supervisor.memory.capacity.mb: 5120
EOF
        fi


	# Attempt to update supervisor.scheduler.meta in storm.yaml
	echo "Attempting to modify storm.yaml..."
	sed -i "/^supervisor.scheduler.meta:/ {n; s/.*/  nodeName: \"$TARGET_VM_NAME\"/}" /conf/storm.yaml


	# Check the exit status of the sed command
	if [ $? -eq 0 ]; then
	  echo "storm.yaml modified successfully."
	else
	  echo "Failed to modify storm.yaml."
	fi

	# Display the updated storm.yaml
	echo "Updated storm.yaml content:"
	cat /conf/storm.yaml
	exec storm supervisor 
	
elif [ "$STORM_ROLE" = "ui" ]; then
  echo "Starting Storm UI..."
  
  # Start the UI process
  exec storm ui 

else
  echo "Unknown STORM_ROLE: $STORM_ROLE. Exiting."
  exit 1
fi
	
