#!/bin/bash

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit
fi

# --- Variables Configuration ---
BRIDGE="ovs-sriov"
PF0="enp1s0f0np0"        # Used as the main Uplink
PF1="enp1s0f1np1"        # Kept out of the bridge to avoid loops
PCI_PF0="0000:01:00.0"
PCI_PF1="0000:01:00.1"
PCI_VF0="0000:01:00.2"
PCI_VF1="0000:01:01.2"
REP0="enp1s0f0npf0vf0"
REP1="enp1s0f1npf1vf0"

echo ">>> Starting OVS Hardware Offload Configuration..."

# 1. Cleanup existing configuration
echo ">>> Cleaning up old configurations..."
ovs-vsctl del-br $BRIDGE 2>/dev/null
ip netns del ns0 2>/dev/null
ip netns del ns1 2>/dev/null
tc qdisc del dev $PF0 ingress 2>/dev/null
tc qdisc del dev $PF1 ingress 2>/dev/null

# 2. Enable Hardware TC Offload on Physical Interfaces
echo ">>> Enabling hw-tc-offload on PFs..."
ethtool -K $PF0 hw-tc-offload off 2>/dev/null
ethtool -K $PF1 hw-tc-offload off 2>/dev/null

# 3. Initialize SR-IOV VFs
# Reset VFs to 0 first to ensure a clean state
echo ">>> Initializing VFs..."
echo 0 > /sys/class/net/$PF0/device/sriov_numvfs
echo 0 > /sys/class/net/$PF1/device/sriov_numvfs
sleep 1
echo 1 > /sys/class/net/$PF0/device/sriov_numvfs
echo 1 > /sys/class/net/$PF1/device/sriov_numvfs

# 4. Configure "eswitch" mode
echo ">>> Setting eswitch mode to legacy..."
# Unbind VFs before changing mode (Required for Mellanox ConnectX-4)
echo $PCI_VF0 > /sys/bus/pci/drivers/mlx5_core/unbind 2>/dev/null
echo $PCI_VF1 > /sys/bus/pci/drivers/mlx5_core/unbind 2>/dev/null

# Set mode to switchdev
# devlink dev eswitch set pci/$PCI_PF0 mode switchdev
# devlink dev eswitch set pci/$PCI_PF1 mode switchdev

# Bind VFs back to the driver
echo $PCI_VF0 > /sys/bus/pci/drivers/mlx5_core/bind
echo $PCI_VF1 > /sys/bus/pci/drivers/mlx5_core/bind

# 5. Open vSwitch Configuration
echo ">>> Configuring Open vSwitch..."
systemctl start openvswitch-switch
ovs-vsctl --no-wait add-br $BRIDGE
ovs-vsctl remove Open_vSwitch . other_config hw-offload 2>/dev/null
ovs-vsctl remove Open_vSwitch . other_config tc-policy 2>/dev/null

# Tuning OVS parameters for better performance
# Flow Aging and Thread Counts
ovs-vsctl set Open_vSwitch . other_config:max-idle=30000
ovs-vsctl set Open_vSwitch . other_config:max-revalidator=10000
ovs-vsctl set Open_vSwitch . other_config:n-handler-threads=4
ovs-vsctl set Open_vSwitch . other_config:n-revalidator-threads=4
systemctl restart openvswitch-switch

# 6. Add Ports to OVS Bridge
# Adding only PF0 as Uplink and both VF Representors
echo ">>> Adding ports to bridge (Excluding PF1 to prevent loops)..."
ovs-vsctl add-port $BRIDGE $PF0
ovs-vsctl add-port $BRIDGE $REP0
ovs-vsctl add-port $BRIDGE $REP1

# Bring up all necessary interfaces
ip link set $PF0 up
ip link set $PF1 up
ip link set $REP0 up
ip link set $REP1 up
ip link set $BRIDGE up

# 7. Setup Network Namespaces and VFs
echo ">>> Setting up Namespaces..."
ip netns add ns0
ip netns add ns1

# Dynamically find VF interface names (they may change after re-bind)
VF0_NAME=$(ls /sys/bus/pci/devices/$PCI_VF0/net/)
VF1_NAME=$(ls /sys/bus/pci/devices/$PCI_VF1/net/)

if [ -z "$VF0_NAME" ] || [ -z "$VF1_NAME" ]; then
    echo "ERROR: VFs not found in /sys/bus/pci/devices/"
    exit 1
fi

# Move VFs to their respective Namespaces
ip link set $VF0_NAME netns ns0
ip link set $VF1_NAME netns ns1

# Configure IP addresses inside Namespaces
ip netns exec ns0 ip addr add 192.168.50.10/24 dev $VF0_NAME
ip netns exec ns1 ip addr add 192.168.50.20/24 dev $VF1_NAME
ip netns exec ns0 ip link set $VF0_NAME up
ip netns exec ns1 ip link set $VF1_NAME up
ip netns exec ns0 ip link set lo up
ip netns exec ns1 ip link set lo up

echo ">>> Configuration Complete!"
echo ">>> Checking FDB table..."
ovs-appctl fdb/show $BRIDGE

# 8.Verify Hardware Offload with Traffic
echo ">>> Testing connectivity and verifying Hardware Offload (TC flower)..."
ip netns exec ns0 ping -c 10 192.168.50.20 &
PING_PID=$!

# Wait for flows to be programmed into hardware
sleep 3

echo ">>> Datapath Flows (Filtering for 'type=ovs' to confirm ovs):"
# This command dumps flows offloaded to hardware via the TC subsystem
ovs-appctl dpctl/dump-flows -m type=ovs

wait $PING_PID
