#!/bin/bash
# Description: Multi-pair Performance Benchmark for OVS HW Offload
# Targets: MART NICs with switchdev mode using Kernel pktgen

# --- Configuration ---
NUM_VFs=2              # Options: 2, 4, 8, 16
DURATION=20            # User defined
PACKET_SIZE=64         # User defined (64 for stress testing PPS)
IP_PREFIX="192.168.50"
NS_PREFIX="ns"

# --- Initialization ---
if ! lsmod | grep -q pktgen; then
    echo ">>> Loading pktgen kernel module..."
    modprobe pktgen
fi

# Function to get interface, IP, MAC and run pktgen for a given pair
# Logic: Pair(i, j) -> ns[i] transmits to ns[j]
configure_pair() {
    local src_idx=$1
    local dst_idx=$2
    local ns_src="${NS_PREFIX}${src_idx}"
    local ns_dst="${NS_PREFIX}${dst_idx}"

    # Auto-detect interfaces
    local src_if=$(ip netns exec $ns_src ip -o addr show | grep "$IP_PREFIX" | awk '{print $2}')
    local dst_if=$(ip netns exec $ns_dst ip -o addr show | grep "$IP_PREFIX" | awk '{print $2}')
    
    [ -z "$src_if" ] && return 1

    local dst_ip=$(ip netns exec $ns_dst ip -o addr show dev $dst_if | awk '/inet / {print $2}' | cut -d/ -f1)
    local dst_mac=$(ip netns exec $ns_dst cat /sys/class/net/$dst_if/address)

    echo "  [Config] $ns_src ($src_if) -> $ns_dst ($dst_ip)"

    # Configure pktgen in source namespace
    ip netns exec $ns_src bash -c "
        echo 'rem_device_all' > /proc/net/pktgen/kpktgend_${src_idx}
        echo 'add_device $src_if' > /proc/net/pktgen/kpktgend_${src_idx}
        echo 'count 0' > /proc/net/pktgen/$src_if
        echo 'pkt_size $PACKET_SIZE' > /proc/net/pktgen/$src_if
        echo 'delay 0' > /proc/net/pktgen/$src_if
        echo 'dst $dst_ip' > /proc/net/pktgen/$src_if
        echo 'dst_mac $dst_mac' > /proc/net/pktgen/$src_if
        echo 'clone_skb 1000' > /proc/net/pktgen/$src_if
        echo 'burst 32' > /proc/net/pktgen/$src_if
    "
}

execute_benchmark() {
    local mode=$1
    echo "====================================================="
    echo ">>> STARTING TEST: $mode"
    echo "====================================================="

    # 1. Stop any existing pktgen instances
    echo ">>> Stopping existing pktgen instances..."
    echo "stop" > /proc/net/pktgen/pgctrl 2>/dev/null
    sleep 2

    # 2. Init each pair based on NUM_VFs
    # Logic : 0->(N-1), 1->(N-2), ...
    local limit=$((NUM_VFs / 2))
    for ((i=0; i<limit; i++)); do
        local j=$((NUM_VFs - 1 - i))
        configure_pair $i $j
    done

    # 3. Run CPU monitoring in background
    sar 1 $((DURATION-1)) > /tmp/sar_cpu.log &
    SAR_PID=$!
    # sar 1 $DURATION | grep "Average" | awk '{print "System Wide Average CPU Idle: "$8"%"}' &

    # 4. Start pktgen for all pairs
    echo ">>> Starting pktgen traffic..."
    for ((i=0; i<limit; i++)); do
        local ns_src="${NS_PREFIX}${i}"
        local src_if=$(ip netns exec $ns_src ip -o addr show | grep "$IP_PREFIX" | awk '{print $2}')
        echo "Starting traffic on $ns_src:$src_if"
        ip netns exec $ns_src bash -c "echo 'start' > /proc/net/pktgen/$src_if" &
    done
    
    echo ">>> Traffic flowing for $DURATION seconds..."
    
    # 5. Wait for DURATION
    sleep $DURATION

    # 6. Stop all pktgen instances
    # This is a workaround since pktgen does not support multi-namespace control
    echo ">>> Stopping traffic..."
    for ((i=0; i<limit; i++)); do
        local ns_src="${NS_PREFIX}${i}"
        local src_if=$(ip netns exec $ns_src ip -o addr show | grep "$IP_PREFIX" | awk '{print $2}' 2>/dev/null)
        if [ -n "$src_if" ]; then
            ip netns exec $ns_src bash -c "echo 'stop' > /proc/net/pktgen/$src_if 2>/dev/null" &
        fi
    done
    echo ">>> Traffic stopped. Collecting results..."
    sleep 2
    # Stop global pktgen control
    echo "stop" > /proc/net/pktgen/pgctrl 2>/dev/null
    wait $SAR_PID

    # 4. Stop pktgen and collect results
    echo ">>> Results:"
    total_pps=0
    for ((i=0; i<limit; i++)); do
        local ns_src="${NS_PREFIX}${i}"
        local src_if=$(ip netns exec $ns_src ip -o addr show | grep "$IP_PREFIX" | awk '{print $2}')
        
        # Read PPS result
        res=$(ip netns exec $ns_src cat /proc/net/pktgen/$src_if | grep "pps" | awk '{print $2}')
        echo " - Pair $i: $res pps"
        total_pps=$((total_pps + res))
    done
    avg_cpu=$(awk '/Average:/ {print 100-$NF}' /tmp/sar_cpu.log)
    echo ">>> Average CPU Utilization during test: $avg_cpu %"
    echo ">>> TOTAL AGGREGATE PPS: $total_pps"
}

# --- Main Flow ---

# Make sure OVS is running
systemctl restart openvswitch-switch
sleep 2

# Check pktgen availability
if [ ! -d /proc/net/pktgen ]; then
    echo "ERROR: pktgen module not loaded or /proc/net/pktgen not available."
    exit 1
fi

# Scenario 1: HW Offload ON
ovs-vsctl set Open_vSwitch . other_config:hw-offload=true
systemctl restart openvswitch-switch
sleep 5
execute_benchmark "HW OFFLOAD ON (ASAP2)"

# Scenario 2: HW Offload OFF
ovs-vsctl set Open_vSwitch . other_config:hw-offload=false
systemctl restart openvswitch-switch
sleep 5
execute_benchmark "HW OFFLOAD OFF (Kernel OVS)"

# Restore
ovs-vsctl set Open_vSwitch . other_config:hw-offload=true
systemctl restart openvswitch-switch
echo ">>> Benchmark Complete."
