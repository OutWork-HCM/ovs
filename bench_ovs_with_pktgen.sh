#!/bin/bash
# Description: Performance Benchmark for OVS Hardware Offload using Kernel pktgen
# Targets: Mellanox ConnectX-4 Lx (switchdev mode)

# --- Configuration ---
DURATION=20
PACKET_SIZE=1500
NS_CLIENT="ns0"
NS_SERVER="ns1"

# Source interface inside ns0 and Target interface inside ns1
SRC_IF="enp1s0f0v0"
DST_IF="eth2"
DST_IP="192.168.50.20"

# Ensure the pktgen kernel module is loaded
if ! lsmod | grep -q pktgen; then
    echo ">>> Loading pktgen kernel module..."
    modprobe pktgen
fi

# Automatically retrieve the Destination MAC address from ns1
# Debug: Check interfaces
echo ">>> Debug: Checking interfaces..."
echo "In $NS_CLIENT:"
ip netns exec $NS_CLIENT ip link show $SRC_IF 2>/dev/null || echo "Interface $SRC_IF not found in $NS_CLIENT"
echo -e "\nIn $NS_SERVER:"
ip netns exec $NS_SERVER ip link show 2>/dev/null | head -20

# Get MAC - FIXED version
DST_MAC=$(ip netns exec $NS_SERVER cat /sys/class/net/$DST_IF/address 2>/dev/null)
if [ -z "$DST_MAC" ]; then
    echo "ERROR: Could not get MAC for $DST_IF"
    echo "Trying alternative method..."
    DST_MAC=$(ip netns exec $NS_SERVER ip link show $DST_IF 2>/dev/null | awk '/link\/ether/ {print $2}')
fi

if [ -z "$DST_MAC" ]; then
    echo "ERROR: No MAC address found for $DST_IF in $NS_SERVER"
    exit 1
fi

echo ">>> Setup Details:"
echo "    Source Interface: $SRC_IF (in $NS_CLIENT)"
echo "    Target MAC:       $DST_MAC (in $NS_SERVER)"
echo "------------------------------------------------"

function run_pktgen_test() {
    local mode=$1
    echo ">>> Starting Test: $mode"

    # Monitor CPU in background
    sar 1 $DURATION | grep "Average" | awk '{print "Average CPU Idle: "$8"%"}' &

    # --- Pktgen Configuration inside Namespace ---
    # Step 1: Initialize pktgen control inside NS
    ip netns exec $NS_CLIENT bash -c "echo 'stop' > /proc/net/pktgen/pgctrl 2>/dev/null"
    sleep 1
    ip netns exec $NS_CLIENT bash -c "echo 'rem_device_all' > /proc/net/pktgen/kpktgend_0 2>/dev/null"
    sleep 1

    # Step 2: Bind device to CPU thread 0
    echo "    Binding $SRC_IF to pktgen thread..."
    if ! ip netns exec $NS_CLIENT bash -c "echo 'add_device $SRC_IF' > /proc/net/pktgen/kpktgend_0 2>&1"; then
        echo "  ERROR: Failed to add device"
        return 1
    fi
    sleep 1

    # Step 3: Setup Packet Parameters
    echo "    Configuring pktgen parameters..."
    ip netns exec $NS_CLIENT bash -c "
        echo 'count 0' > /proc/net/pktgen/$SRC_IF 2>/dev/null           # 0 means continuous flow
        echo 'pkt_size $PACKET_SIZE' > /proc/net/pktgen/$SRC_IF 2>/dev/null          # Minimum packet size to stress CPU
        echo 'delay 0' > /proc/net/pktgen/$SRC_IF 2>/dev/null                    # No delay between packets
        echo 'dst $DST_IP' > /proc/net/pktgen/$SRC_IF 2>/dev/null
        echo 'dst_mac $DST_MAC' > /proc/net/pktgen/$SRC_IF 2>/dev/null
        echo 'clone_skb 1000' > /proc/net/pktgen/$SRC_IF 2>/dev/null      # Transmit same packet 1000 times before re-processing
        echo 'burst 32' > /proc/net/pktgen/$SRC_IF 2>/dev/null            # Send 32 packets in a single batch
    "
    sleep 1
    # Verify Configuration
    echo "    Current pktgen configuration:"
    ip netns exec $NS_CLIENT bash -c "
        cat /proc/net/pktgen/$SRC_IF | grep -E 'count:|pkt_size:|dst:|dst_mac:' | head -5
    "
    sleep 1

    # Step 4: Start Traffic
    echo "    Starting traffic for $DURATION seconds..."
    ip netns exec $NS_CLIENT bash -c "
        echo 'start' > /proc/net/pktgen/pgctrl 2>/dev/null
    " &
    PG_PID=$!
    # Wait for the duration
    echo ">>> Traffic is flowing. Waiting for $DURATION seconds..."
    sleep $DURATION

    # Step 5: Stop Traffic
    echo "    Stopping traffic..."
    ip netns exec $NS_CLIENT bash -c "echo 'stop' > /proc/net/pktgen/pgctrl 2>/dev/null"
    sleep 1
    # Display performance statistics
    echo ">>> Statistics for $mode:"
    ip netns exec $NS_CLIENT cat /proc/net/pktgen/$SRC_IF 2>/dev/null | grep -E "Result|pps|errors|MB/sec" | head -10
    # Cleanup
    kill $PG_PID 2>/dev/null || true
    echo "------------------------------------------------"
}

# --- Execution Flow ---

# Scenario 1: Hardware Offload ENABLED (OVS ASAP2)
# Traffic should be handled by the ConnectX-4 ASIC
ovs-vsctl set Open_vSwitch . other_config:hw-offload=true
systemctl restart openvswitch-switch
sleep 5 # Allow time for OVS to re-initialize
echo " >>> Testing with Hardware Offload ENABLED..."
echo " Current OVS other_config:"
ovs-vsctl get Open_vSwitch . other_config
run_pktgen_test "HW OFFLOAD ON (dp:tc)"

# Scenario 2: Hardware Offload DISABLED (Standard Kernel OVS)
# Traffic will be handled by the Host CPU
ovs-vsctl set Open_vSwitch . other_config:hw-offload=false
systemctl restart openvswitch-switch
sleep 5
echo " >>> Testing with Hardware Offload DISABLED..."
echo " Current OVS other_config:"
ovs-vsctl get Open_vSwitch . other_config
run_pktgen_test "HW OFFLOAD OFF (dp:ovs)"

# Final Cleanup: Restore Hardware Offload for production
echo ">>> Restoring Hardware Offload to ENABLED..."
ovs-vsctl set Open_vSwitch . other_config:hw-offload=true
systemctl restart openvswitch-switch
sleep 5
echo ">>> Benchmark Complete. HW Offload restored to ON."
