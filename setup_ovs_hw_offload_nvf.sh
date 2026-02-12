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
NUM_VFS=16

# Prefixes for Representors and Namespaces
NS_PREFIX="ns"

# Prefixes for Representors and Namespaces
NS_PREFIX="ns"
IP_PREFIX="192.168.50"

# --- Recommendation 4: CPU Governance Tuning ---
# Set CPU governor to performance to prevent latency spikes
echo ">>> Tuning: Setting CPU governor to performance..."
if command -v cpupower &> /dev/null; then
    cpupower frequency-set -g performance
else
    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo performance > $gov 2>/dev/null || true
    done
fi


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

# --- Recommendation 2: Enable Jumbo Frames (MTU 9000) ---
# Set MTU 9000 on Uplink PF for high-throughput testing
echo ">>> Tuning: Setting MTU 9000 on PF $PF0..."
ip link set dev $PF0 mtu 9000


# 5. Enable hw-tc-offload on PFs (Uplink port) and VF Port Representors
echo ">>> Enabling hw-tc-offload on PFs..."
ethtool -K $PF0 hw-tc-offload on 2>/dev/null
# Find and add Representor interfaces for each VF
for i in $(seq 0 $(($NUM_VFS - 1))); do
    TARGET_NAME="pf0vf$i"
    REAL_REP_NAME=""

    # Find the representor by checking phys_port_name
    # Find the representor by checking phys_port_name
    # --- Recommendation 3: Robustness - Check for Device Existence ---
    # Wait for representor to be created by the driver
    for attempt in {1..10}; do
        for dev_path in /sys/class/net/*/phys_port_name; do
            if [ -f "$dev_path" ]; then
                content=$(cat "$dev_path" 2>/dev/null)
                if [ "$content" == "$TARGET_NAME" ]; then
                    REAL_REP_NAME=$(basename $(dirname "$dev_path"))
                    break 2
                fi
            fi
        done
        sleep 0.5
    done

    if [ -n "$REAL_REP_NAME" ]; then
        echo ">>> Found Representor: $REAL_REP_NAME for VF $i"
        echo ">>> Enabling hw-tc-offload on $REAL_REP_NAME..."
        ethtool -K $REAL_REP_NAME hw-tc-offload on 2>/dev/null
        
        # --- Recommendation 2: Enable Jumbo Frames (MTU 9000) ---
        # Set MTU 9000 on Representor
        echo ">>> Tuning: Setting MTU 9000 on Representor $REAL_REP_NAME..."
        ip link set dev $REAL_REP_NAME mtu 9000
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
    # --- Recommendation 3: Robustness - Check for Device Existence ---
    # Wait for representor to be created by the driver
    for attempt in {1..10}; do
        for dev_path in /sys/class/net/*/phys_port_name; do
            if [ -f "$dev_path" ]; then
                content=$(cat "$dev_path" 2>/dev/null)
                if [ "$content" == "$TARGET_NAME" ]; then
                    REAL_REP_NAME=$(basename $(dirname "$dev_path"))
                    break 2
                fi
            fi
        done
        sleep 0.5
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

# Unbind all VFs before changing mode
# VFS_PCI_LIST=$(ls -d /sys/bus/pci/devices/$PCI_PF0/virtfn* | xargs -l readlink | xargs -I {} basename {})
# VFS_PCI_LIST=$(grep PCI_SLOT_NAME /sys/class/net/$PF0/device/virtfn*/uevent | cut -d'=' -f2)
#
# for pci in $VFS_PCI_LIST; do
#     echo $pci > /sys/bus/pci/drivers/mlx5_core/unbind 2>/dev/null
# done
# sleep 20

# Steering Mode & Match Mode
# devlink dev param set pci/$PCI_PF0 name flow_steering_mode value "smfs" cmode runtime
# echo metadata > /sys/class/net/$PF0/compat/devlink/vport_match_mode


# Rebind VFs to mlx5_core
# for pci in $VFS_PCI_LIST; do
#     echo $pci > /sys/bus/pci/drivers/mlx5_core/bind 2>/dev/null
# done
# sleep 15

# 8. Setup Network Namespaces and VFs
echo ">>> Setting up $NUM_VFS Namespaces..."

# Create namespaces and move VFs into them
for i in $(seq 0 $(($NUM_VFS - 1))); do
    NS_NAME="${NS_PREFIX}${i}"
    ip netns add $NS_NAME

    # Get PCI address of VF
    VF_PCI=$(readlink /sys/class/net/$PF0/device/virtfn$i | cut -d'/' -f2)
    # Get VF interface name
    VF_INTERFACE=$(ls /sys/bus/pci/devices/$VF_PCI/net/)

    if [ -z "$VF_INTERFACE" ]; then
        echo "Warning: VF $i interface not found!"
        continue
    fi

    # Move VF to namespace
    ip link set $VF_INTERFACE netns $NS_NAME

    # Configure IP inside namespace and bring up Interfaces
    # Assign IPs from 192.168.50.10 to 192.168.50.(10+NUM_VFS-1)
    IP_ADDR="${IP_PREFIX}.$(($i + 10))"
    ip netns exec $NS_NAME ip addr add ${IP_ADDR}/24 dev $VF_INTERFACE
    ip netns exec $NS_NAME ip link set $VF_INTERFACE up
    ip netns exec $NS_NAME ip link set lo up

    # --- Recommendation 2: Enable Jumbo Frames (MTU 9000) ---
    # Set MTU 9000 on VF interface inside namespace
    echo ">>> Tuning: Setting MTU 9000 on VF $VF_INTERFACE inside $NS_NAME..."
    ip netns exec $NS_NAME ip link set dev $VF_INTERFACE mtu 9000

    echo "Configured $NS_NAME with IP $IP_ADDR"

done

echo ">>> Configuration Complete!"

echo ">>> Bringing up OVS bridge $BRIDGE..."
ip link set $BRIDGE up

# 8. Verify
echo ">>> Testing connectivity between ns0 and other..."
# Get IP of ns0
NS0_IP="${IP_PREFIX}.10"

for i in $(seq 1 $(($NUM_VFS - 1))); do
    TARGET_IP="${IP_PREFIX}.$(($i + 10))"

    echo -n "Pinging $TARGET_IP từ ns0: "
    if ip netns exec ns0 ping -c 2 -W 1 $TARGET_IP > /dev/null; then
        echo "SUCCESS"
    else
        echo "FAILED"
    fi
done

echo ">>> Waiting 2 second to hw-offload setuped..."
sleep 2

echo ">>> CHECK HARDWARE OFFLOAD:"
# Check OVS flows for offloading
ovs-appctl dpctl/dump-flows -m | grep "eth_type(0x0800)" | grep "offloaded:yes"
if [ $? -eq 0 ]; then
    echo ">>> Hardware offload is ENABLED for IP flows."
else
    echo ">>> Hardware offload is NOT enabled for IP flows."
fi

sleep 1

echo ">>> All done!"

# --- Recommendation 1: Fix IP & Namespace Mismatch (Clarification) ---
echo "================================================================"
echo "   Namespace IP Assignment Map (Use these for Benchmarks)"
echo "================================================================"
echo "   Namespace       IP Address"
echo "   ---------       ----------"
for i in $(seq 0 $(($NUM_VFS - 1))); do
    NS_NAME="${NS_PREFIX}${i}"
    IP_ADDR="${IP_PREFIX}.$(($i + 10))"
    echo "   $NS_NAME            $IP_ADDR"
done
echo "================================================================"
echo "Note: Update your benchmark scripts to match these IPs."

