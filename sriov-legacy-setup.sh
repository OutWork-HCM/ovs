#!/bin/bash

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit
fi

# --- Configuration ---
PF1="enp1s0f1np1"
NUM_VFS=4
MTU_VAL=8996
VENDOR="Intel"

echo ">>> Starting SR-IOV Legacy Configuration on $PF1..."

# If the detected NIC vendor is Intel, reload the 'ice' driver.
# This ensures the driver is properly initialized for Intel network cards.
if [ "$VENDOR" == "Intel" ]; then
   echo ">>> Reloading 'ice' driver..."
   rmmod ice 2>/dev/null
   modprobe ice 2>/dev/null
   sleep 3
fi

ip link set $PF1 up
ip link set $PF1 mtu $MTU_VAL

echo ">>> Initializing $NUM_VFS VFs on $PF1..."
echo 0 > /sys/class/net/$PF1/device/sriov_numvfs
sleep 1
echo $NUM_VFS > /sys/class/net/$PF1/device/sriov_numvfs
sleep 2

# Loop over each Virtual Function (VF) index for the given Physical Function (PF1)
for i in $(seq 0 $(($NUM_VFS - 1))); do
    echo ">>> Configuring VF $i..."
    # Enable the VF on the physical interface
    ip link set $PF1 vf $i state enable
    
    # Get the network interface name associated with this VF
    VF_NAME=$(ls /sys/class/net/$PF1/device/virtfn$i/net/ 2>/dev/null)
    if [ -n "$VF_NAME" ]; then
        # Set the MTU for the VF and bring it up if the interface exists
        ip link set $VF_NAME mtu $MTU_VAL
        ip link set $VF_NAME up
    fi
done

echo ""
echo "========================================================="
echo "   SR-IOV LEGACY PCI MAPPING (For Proxmox Passthrough)"
echo "========================================================="
printf "%-10s | %-15s | %-15s\n" "VF Index" "Interface" "PCI Address"
echo "---------------------------------------------------------"

for i in $(seq 0 $(($NUM_VFS - 1))); do
    VF_PCI=$(basename $(readlink /sys/class/net/$PF1/device/virtfn$i))
    VF_NAME=$(ls /sys/class/net/$PF1/device/virtfn$i/net/ 2>/dev/null | head -n 1)
    printf "%-10s | %-15s | %-15s\n" "VF $i" "${VF_NAME:-'N/A'}" "$VF_PCI"
done

echo "========================================================="
echo ">>> Setup Complete!"
