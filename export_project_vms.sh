#!/bin/bash

# Output CSV file
OUTPUT="project_vms.csv"

# CSV header
echo "Project,VM_ID,VM_Name,Status,Host,Flavor,VCPUs,RAM_MB,Disk_GB" > $OUTPUT

# Loop through all projects
openstack project list -f value -c Name | while read PROJECT; do
    # Loop through all VMs in the project
    openstack server list --project $PROJECT -f value -c ID -c Name -c Status -c Host | while read VM_ID VM_NAME STATUS HOST; do
        # Get VM flavor
        FLAVOR=$(openstack server show $VM_ID -f value -c flavor)
        # Get flavor resources
        read VCPU RAM DISK <<< $(openstack flavor show $FLAVOR -f value -c vcpus -c ram -c disk)
        # Append to CSV
        echo "$PROJECT,$VM_ID,$VM_NAME,$STATUS,$HOST,$FLAVOR,$VCPU,$RAM,$DISK" >> $OUTPUT
    done
done

echo "CSV export complete: $OUTPUT"
