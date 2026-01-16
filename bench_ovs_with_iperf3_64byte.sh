#!/bin/bash
# Description: Benchmark CPU usage for OVS Hardware Offload

# Variables
DURATION=20
SERVER_IP="192.168.50.20"
NS_CLIENT="ns0"
NS_SERVER="ns1"

function run_test() {
    local mode=$1
    echo ">>> Running Benchmark in mode: $mode"
    
    # Start iperf3 server in background
    ip netns exec $NS_SERVER iperf3 -s -1 > /dev/null 2>&1 &
    sleep 2

    # Measure average CPU idle percentage during iperf3 run
    # 'sar' from sysstat package is great for this
    sar 1 $DURATION | grep "Average" | awk '{print "Average CPU Idle: "$8"%"}' &
    
    # Run iperf3 client
    # -u: upd                                                                                                                 │
    # -l 64: Packet size 64                                                                                                   │
    # -b 0: unlimited bandwidth                                                                                               │
    # -P 64: Paralle 64 flows                                                                                                 │
    # -t 30: 30s runtime                                                                                                      │
    ip netns exec $NS_CLIENT iperf3 -c $SERVER_IP -u -l 64 -b 0 -t $DURATION -P 64 | grep "receiver"
    
    echo "------------------------------------------------"
}

# --- Test 1: HW Offload ON ---
ovs-vsctl set Open_vSwitch . other_config:hw-offload=true
systemctl restart openvswitch-switch
sleep 5
run_test "OFFLOAD ON (dp:tc)"

# --- Test 2: HW Offload OFF ---
ovs-vsctl set Open_vSwitch . other_config:hw-offload=false
systemctl restart openvswitch-switch
sleep 5
run_test "OFFLOAD OFF (dp:ovs)"

# Restore settings
ovs-vsctl set Open_vSwitch . other_config:hw-offload=true
systemctl restart openvswitch-switch
