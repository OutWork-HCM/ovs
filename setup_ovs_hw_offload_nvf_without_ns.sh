#!/bin/bash

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit
fi

# --- Variables Configuration ---
BRIDGE="ovs-sriov"
PF0="enp1s0f0np0"
PF1="enp1s0f1np1"
VENDOR="Intel"

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

# Get PCI addresses of PFs
# PCI_PF0="0000:01:00.0"
# PCI_PF0=$(ethtool -i $PF0 | grep bus-info | awk '{print $2}')
PCI_PF0=$(grep PCI_SLOT_NAME /sys/class/net/$PF0/device/uevent | sed 's:.*PCI_SLOT_NAME=::')
# PCI_PF1="0000:01:00.1"
PCI_PF1=$(grep PCI_SLOT_NAME /sys/class/net/$PF1/device/uevent | sed 's:.*PCI_SLOT_NAME=::')

# Number of VFs to configure
NUM_VFS=2

# Prefixes for Representors and Namespaces
NS_PREFIX="ns"
IP_PREFIX="192.168.50"

echo ">>> Starting OVS Hardware Offload Configuration for $NUM_VFS VFs..."

# 1. Cleanup existing configuration
echo ">>> Cleaning up old configurations..."
ovs-vsctl del-br $BRIDGE 2>/dev/null
# Remove existing namespaces
for i in $(seq 0 $(($NUM_VFS - 1))); do
    ip netns del ${NS_PREFIX}${i} 2>/dev/null
done
# Delete existing ingress qdiscs
tc qdisc del dev $PF0 ingress 2>/dev/null
tc qdisc del dev $PF1 ingress 2>/dev/null

echo ">>> Configuring Open vSwitch..."
echo ">>> Creating OVS bridge $BRIDGE..."
systemctl start openvswitch-switch
ovs-vsctl --no-wait add-br $BRIDGE
echo ">>> Add $PF0 to bridge $BRIDGE..."
ovs-vsctl --no-wait add-port $BRIDGE $PF0

# 2. Initialize SR-IOV VFs
echo ">>> Initializing $NUM_VFS VFs on $PF0..."
echo 0 > /sys/class/net/$PF0/device/sriov_numvfs
sleep 1

# 3. Configure "switchdev" mode
echo ">>> Setting eswitch mode to switchdev..."
# Set mode to switchdev
echo ">>> Setting $PF0 ($PCI_PF0) to switchdev mode..."
devlink dev eswitch set pci/$PCI_PF0 mode switchdev

# 4. Create VFs
# Set number of VFs
echo $NUM_VFS > /sys/class/net/$PF0/device/sriov_numvfs
sleep 2
# Assign MAC addresses to VFs
for i in $(seq 0 $(($NUM_VFS - 1))); do
    MAC_ADDR=$(printf 'e4:11:22:33:44:%02x' $i)
    ip link set $PF0 vf $i mac $MAC_ADDR
done
sleep 1

# 5. Enable hw-tc-offload on PFs (Uplink port) and VF Port Representors
echo ">>> Enabling hw-tc-offload on PFs..."
ethtool -K $PF0 hw-tc-offload on 2>/dev/null
# Find and add Representor interfaces for each VF
for i in $(seq 0 $(($NUM_VFS - 1))); do
    TARGET_NAME="pf0vf$i"
    REAL_REP_NAME=""

    # Find the representor by checking phys_port_name
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
        echo ">>> Found Representor: $REAL_REP_NAME for VF $i"
        echo ">>> Enabling hw-tc-offload on $REAL_REP_NAME..."
        ethtool -K $REAL_REP_NAME hw-tc-offload on 2>/dev/null
    else
        echo ">>> ERROR: Could not find Representor for VF $i"
    fi
done

# 6. Open vSwitch Configuration
ovs-vsctl set Open_vSwitch . other_config:hw-offload=true
ovs-vsctl remove Open_vSwitch . other_config tc-policy 2>/dev/null
# ovs-vsctl set Open_vSwitch . other_config:tc-policy=skip_sw 2>/dev/null

# Tuning OVS parameters
ovs-vsctl set Open_vSwitch . other_config:max-idle=30000
# ovs-vsctl set Open_vSwitch . other_config:max-revalidator=10000
# ovs-vsctl set Open_vSwitch . other_config:n-handler-threads=1
# ovs-vsctl set Open_vSwitch . other_config:n-revalidator-threads=1
ovs-vsctl remove Open_vSwitch . other_config max-revalidator 2>/dev/null
ovs-vsctl remove Open_vSwitch . other_config n-handler-threads 2>/dev/null
ovs-vsctl remove Open_vSwitch . other_config n-revalidator-threads 2>/dev/null
systemctl restart openvswitch-switch

# 7. Add Ports to OVS Bridge
echo ">>> Adding $NUM_VFS Representors to bridge..."

# Find and add Representor interfaces for each VF
for i in $(seq 0 $(($NUM_VFS - 1))); do
    TARGET_NAME="pf0vf$i"
    REAL_REP_NAME=""

    # Find the representor by checking phys_port_name
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
        echo ">>> Found Representor: $REAL_REP_NAME for VF $i"
        ovs-vsctl --may-exist add-port $BRIDGE $REAL_REP_NAME
        ip link set $REAL_REP_NAME up
    else
        echo ">>> ERROR: Could not find Representor for VF $i"
    fi
done

ip link set $PF0 up

echo ">>> Configuration Complete!"

echo ">>> Bringing up OVS bridge $BRIDGE..."
ip link set $BRIDGE up

sleep 1

echo ">>> All done!"
