#!/bin/bash

echo "===== OpenStack Host Resource Report ====="
echo

# Loop through all hypervisor hosts
for host in $(openstack hypervisor list -f value -c "Hypervisor Hostname"); do

    # Get host totals
    VCPU_TOTAL=$(openstack hypervisor show $host -f value -c vcpus)
    VCPU_USED=$(openstack hypervisor show $host -f value -c vcpus_used)
    MEM_TOTAL=$(openstack hypervisor show $host -f value -c memory_mb)
    MEM_USED=$(openstack hypervisor show $host -f value -c memory_mb_used)
    DISK_TOTAL=$(openstack hypervisor show $host -f value -c local_gb)
    DISK_USED=$(openstack hypervisor show $host -f value -c local_gb_used)

    echo "Host: $host"
    echo "Total VCPU: $VCPU_TOTAL, Used VCPU: $VCPU_USED, Total Mem(MB): $MEM_TOTAL, Used Mem(MB): $MEM_USED, Total Disk(GB): $DISK_TOTAL, Used Disk(GB): $DISK_USED"
    echo

    # Temporary file to store project totals
    TMP_FILE=$(mktemp)
    > $TMP_FILE

    # List all VMs on this host with project info
    openstack server list --all-projects --host $host -f value -c ID -c Name -c Project | while read VM_ID VM_NAME PROJECT; do
        # Get flavor
        FLAVOR=$(openstack server show $VM_ID -f value -c flavor)
        # Get flavor resources
        F_VCPU=$(openstack flavor show $FLAVOR -f value -c vcpus)
        F_RAM=$(openstack flavor show $FLAVOR -f value -c ram)
        F_DISK=$(openstack flavor show $FLAVOR -f value -c disk)

        # Print VM info
        printf "Project: %-10s VM: %-15s Flavor: %-10s CPU: %-2s RAM(MB): %-5s Disk(GB): %-3s\n" \
        "$PROJECT" "$VM_NAME" "$FLAVOR" "$F_VCPU" "$F_RAM" "$F_DISK"

        # Update project totals in temp file
        # Format: project cpu mem disk
        EXISTING=$(grep "^$PROJECT " $TMP_FILE)
        if [ -z "$EXISTING" ]; then
            echo "$PROJECT $F_VCPU $F_RAM $F_DISK" >> $TMP_FILE
        else
            OLD_CPU=$(echo $EXISTING | awk '{print $2}')
            OLD_RAM=$(echo $EXISTING | awk '{print $3}')
            OLD_DISK=$(echo $EXISTING | awk '{print $4}')
            NEW_CPU=$((OLD_CPU + F_VCPU))
            NEW_RAM=$((OLD_RAM + F_RAM))
            NEW_DISK=$((OLD_DISK + F_DISK))
            # Replace the old line
            grep -v "^$PROJECT " $TMP_FILE > ${TMP_FILE}.tmp
            mv ${TMP_FILE}.tmp $TMP_FILE
            echo "$PROJECT $NEW_CPU $NEW_RAM $NEW_DISK" >> $TMP_FILE
        fi
    done

    # Print project totals
    echo
    echo "Project Totals on $host:"
    while read P CPU MEM DISK; do
        echo "  $P -> CPU: $CPU, RAM: ${MEM} MB, Disk: ${DISK} GB"
    done < $TMP_FILE

    rm -f $TMP_FILE

    echo
    echo "-----------------------------------------------"
    echo

done
