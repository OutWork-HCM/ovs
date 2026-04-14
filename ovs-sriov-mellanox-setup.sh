#!/bin/bash

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit
fi

# --- Variables Configuration ---
BRIDGE="ovs_mellanox"
PF0="enp1s0f0np0"
PF1="enp1s0f1np1"
# Proxmox uses different naming convention for interfaces, adjust accordingly if needed
#PF0="nic2"
#PF1="nic3"
VENDOR="Mellanox"
NUM_VFS=4
MTU_VAL=8996

# Reload driver for Intel NICs to ensure clean state
if [ "$VENDOR" == "Intel" ]; then
    rmmod ice 2>/dev/null
    modprobe ice 2>/dev/null
    sleep 2
elif [ "$VENDOR" == "Mellanox" ]; then
    rmmod mlx5_core mlx5_ib 2>/dev/null
    modprobe mlx5_core 2>/dev/null
    sleep 2
fi

PCI_PF0=$(grep PCI_SLOT_NAME /sys/class/net/$PF0/device/uevent | sed 's:.*PCI_SLOT_NAME=::')
PCI_PF1=$(grep PCI_SLOT_NAME /sys/class/net/$PF1/device/uevent | sed 's:.*PCI_SLOT_NAME=::')

echo ">>> Starting OVS Hardware Offload Configuration for $NUM_VFS VFs..."

# 1. Cleanup existing configuration
echo ">>> Cleaning up old configurations..."
ovs-vsctl del-br $BRIDGE 2>/dev/null
tc qdisc del dev $PF0 ingress 2>/dev/null

echo ">>> Configuring Open vSwitch..."
systemctl start openvswitch-switch
ovs-vsctl --no-wait add-br $BRIDGE
sleep 2
ip link set $PF0 mtu $MTU_VAL
ip link set $BRIDGE mtu $MTU_VAL

# 2. Initialize SR-IOV VFs
echo ">>> Initializing $NUM_VFS VFs on $PF0..."
echo 0 > /sys/class/net/$PF0/device/sriov_numvfs
sleep 1

# 3. Configure "switchdev" mode
echo ">>> Setting $PF0 ($PCI_PF0) to switchdev mode..."
devlink dev eswitch set pci/$PCI_PF0 mode switchdev

# 4. Create VFs
echo $NUM_VFS > /sys/class/net/$PF0/device/sriov_numvfs
sleep 2

# 5. Enable hw-tc-offload and Configure OVS
ethtool -K $PF0 hw-tc-offload on 2>/dev/null
ovs-vsctl set Open_vSwitch . other_config:hw-offload=true
# Update base on Proxmox Docs: Ensure TC policy is set for hardware path
# ovs-vsctl set Open_vSwitch . other_config:tc-policy=skip_sw
ovs-vsctl set Open_vSwitch . other_config:max-idle=30000
systemctl restart openvswitch-switch

# --- Array to store mapping for the final report ---
DECLARE_MAPPING=()

# 6. Find Representors, Add to OVS and Map to VFs
echo ">>> Mapping VFs to Representors..."

# Loop through each Virtual Function (VF) index to configure its representor and real interface
# - For each VF:
#   A. Find the real VF network interface name (used by VM)
#   B. Find the corresponding representor interface name (used by OVS)
#   C. Configure OVS and enable hardware offload for the representor
#   D. Set MTU and bring up both interfaces
#   E. Store mapping for reporting

# Get PCI address of PF (e.g., 0000:04:00.0)
PCI_PF_FULL=$PCI_PF0

for i in $(seq 0 $(($NUM_VFS - 1))); do
    # A. Find the real VF network interface name (the one assigned to VM)
    VF_REAL_NAME=$(ls /sys/class/net/$PF0/device/virtfn$i/net/ 2>/dev/null)

    # B. Find the representor interface name
    REAL_REP_NAME=""
    TARGET_NAME="pf0vf$i" # IMPORTANT: Must match the index i

    # Loop through all network devices to find the representor
    for dev in /sys/class/net/*; do
        # Only check interfaces with phys_port_name (characteristic of representors)
        if [ -f "$dev/phys_port_name" ]; then
            content=$(cat "$dev/phys_port_name" 2>/dev/null)
            
            # Check if phys_port_name matches the target name for this VF
            if [ "$content" == "$TARGET_NAME" ]; then
                # Ensure this device belongs to the same physical card as the PF
                # Mellanox representors share PCI ID with the original PF
                DEV_PCI=$(grep PCI_SLOT_NAME "$dev/device/uevent" | cut -d'=' -f2)
                
                if [ "$DEV_PCI" == "$PCI_PF_FULL" ]; then
                    REAL_REP_NAME=$(basename "$dev")
                    break
                fi
            fi
        fi
    done

    # Avoid the case where the VF is mistakenly identified as its own representor
    if [ "$REAL_REP_NAME" == "$VF_REAL_NAME" ]; then
        REAL_REP_NAME="" # If they match, it's a logic error in switchdev
    fi

    if [ -n "$REAL_REP_NAME" ]; then
        echo ">>> VF $i: Representor=$REAL_REP_NAME, Real Interface=${VF_REAL_NAME:-'Unknown'}"
        
        # Enable hardware TC offload on the representor
        ethtool -K $REAL_REP_NAME hw-tc-offload on 2>/dev/null
        # Add the representor to the OVS bridge
        ovs-vsctl --may-exist add-port $BRIDGE $REAL_REP_NAME
        
        # Set MTU and bring up the representor interface
        ip link set $REAL_REP_NAME mtu $MTU_VAL up
        # Set MTU and bring up the real VF interface (if present)
        if [ -n "$VF_REAL_NAME" ]; then
            ip link set $VF_REAL_NAME mtu $MTU_VAL up
        fi

        # Save mapping for reporting
        DECLARE_MAPPING+=("$i|${VF_REAL_NAME:-'N/A'}|$REAL_REP_NAME")
    else
        echo ">>> ERROR: Could not find Representor for VF $i (Target: $TARGET_NAME)"
    fi
done

# --- Host Connectivity Configuration ---
# Update base on Proxmox Docs: Bridges should not have IPs. Use an Internal Port for Host IP
echo ">>> Configuring Host Internal Port (mgmt1)..."
ovs-vsctl --may-exist add-port $BRIDGE mgmt1 -- set interface mgmt1 type=internal
ip link set mgmt1 mtu $MTU_VAL
ip addr add 20.20.20.1/24 dev mgmt1
ip link set mgmt1 up

ovs-vsctl --no-wait add-port $BRIDGE $PF0
ip link set $PF0 up
ip link set $BRIDGE up

# --- FINAL SUMMARY TABLE ---
echo ""
echo "========================================================="
echo "   SR-IOV HW OFFLOAD MAPPING SUMMARY"
echo "========================================================="
printf "%-10s | %-20s | %-20s\n" "VF Index" "VF Interface (Real)" "Representor (OVS)"
echo "---------------------------------------------------------"
for item in "${DECLARE_MAPPING[@]}"; do
    IFS='|' read -r index vfname repname <<< "$item"
    printf "%-10s | %-20s | %-20s\n" "VF $index" "$vfname" "$repname"
done
echo "========================================================="
echo ">>> Configuration Complete!"
