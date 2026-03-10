#!/bin/bash

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit
fi

# --- Variables Configuration ---
BRIDGE="ovs_sriov"
# PF0="enp1s0f0np0"
# PF1="enp1s0f1np1"
# Proxmox uses different naming convention for interfaces, adjust accordingly if needed
PF0="nic2"
PF1="nic3"
VENDOR="Intel"
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
ovs-vsctl set Open_vSwitch . other_config:tc-policy=skip_sw
ovs-vsctl set Open_vSwitch . other_config:max-idle=30000
systemctl restart openvswitch-switch

# --- Array to store mapping for the final report ---
DECLARE_MAPPING=()

# 6. Find Representors, Add to OVS and Map to VFs
echo ">>> Mapping VFs to Representors..."

for i in $(seq 0 $(($NUM_VFS - 1))); do
    # A. Find Real VF Name (The interface the VM/App will use)
    # This looks into the PCI tree to find the net interface name assigned to this VF
    VF_REAL_NAME=$(ls /sys/class/net/$PF0/device/virtfn$i/net/ 2>/dev/null)
    
    # B. Find Representor Name
    TARGET_NAME="pf0vf$i"
    REAL_REP_NAME=""
    for dev_path in /sys/class/net/*/phys_port_name; do
        if [ -f "$dev_path" ]; then
            content=$(cat "$dev_path" 2>/dev/null)
            if [ "$content" == "$TARGET_NAME" ]; then
                REAL_REP_NAME=$(basename $(dirname "$dev_path"))
                break
            fi
        fi
    done

    if [ -n "$REAL_REP_NAME" ]; then
        echo ">>> VF $i: Representor=$REAL_REP_NAME, Real Interface=${VF_REAL_NAME:-'Unknown'}"
        ethtool -K $REAL_REP_NAME hw-tc-offload on 2>/dev/null
        ovs-vsctl --may-exist add-port $BRIDGE $REAL_REP_NAME
	ip link set $REAL_REP_NAME mtu $MTU_VAL
	ip link set $VF_REAL_NAME mtu $MTU_VAL 2>/dev/null
        ip link set $REAL_REP_NAME up
        ip link set $VF_REAL_NAME up 2>/dev/null
        
        # Save to array for final summary
        DECLARE_MAPPING+=("$i|${VF_REAL_NAME:-'N/A'}|$REAL_REP_NAME")
    else
        echo ">>> ERROR: Could not find Representor for VF $i"
    fi
done

# --- Host Connectivity Configuration ---
# Update base on Proxmox Docs: Bridges should not have IPs. Use an Internal Port for Host IP
echo ">>> Configuring Host Internal Port (mgmt0)..."
ovs-vsctl --may-exist add-port $BRIDGE mgmt0 -- set interface mgmt0 type=internal
ip link set mgmt0 mtu $MTU_VAL
ip addr add 10.10.10.1/24 dev mgmt0
ip link set mgmt0 up

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
