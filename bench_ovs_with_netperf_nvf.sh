#!/bin/bash
# bench_ovs_with_netperf_nvf.sh
# Optimized Parallel Benchmark Script for OVS with Netperf and Network Namespaces
#
# This script automates the benchmarking of Open vSwitch (OVS) using netperf
# across multiple network namespaces (VFs), running parallel client-server pairs.
# It optimizes system parameters, launches netserver/netperf in isolated namespaces,
# collects throughput results, and provides both detailed and aggregated reports.
#
# Usage:
#   - Adjust NUM_VFs to set the number of virtual functions (must be even).
#   - Ensure network namespaces and IPs are pre-configured.
#   - Run as root for namespace and sysctl operations.

NUM_VFs=2                # Number of Virtual Functions (VFs) / network namespaces (must be even)
DURATION=60              # Duration of each netperf test in seconds
IP_BASE="192.168.50"     # Base IP for server assignment
NS_PREFIX="ns"           # Prefix for network namespace names
NUM_PAIRS=$((NUM_VFs / 2)) # Number of client-server pairs
LOG_FILE="/tmp/netperf_raw.log" # File to store raw netperf results

# Clear old log file
> $LOG_FILE

# System optimization (increase socket buffer limits)
sysctl -w net.core.rmem_max=16777216 > /dev/null
sysctl -w net.core.wmem_max=16777216 > /dev/null

# Function: start_server
# Starts a netserver instance in a given namespace, pinned to a specific CPU core.
# Arguments:
#   $1 - Server index (namespace and port are derived from this)
function start_server() {
    local s_idx=$1
    local ns_server="${NS_PREFIX}${s_idx}"
    local port=$((22110 + s_idx))
    # Server runs on even-numbered CPU cores (0, 2, 4...)
    local server_cpu=$(( (s_idx * 2) % 32 ))
    ip netns exec $ns_server taskset -c $server_cpu netserver -p $port > /dev/null 2>&1
}

# Function: start_client
# Starts a netperf client in a given namespace, targeting a server namespace/IP/port.
# Arguments:
#   $1 - Client index (namespace and CPU core)
#   $2 - Server index (namespace, IP, and port)
function start_client() {
    local c_idx=$1  
    local s_idx=$2  
    local ns_client="${NS_PREFIX}${c_idx}"
    local server_ip="${IP_BASE}.$(($s_idx + 10))"
    local port=$((22110 + s_idx))
    
    # Client runs on odd-numbered CPU cores (1, 3, 5...)
    local client_cpu=$(( (c_idx * 2 + 1) % 32 ))
    
    # Display pairing information
    echo "Pairing: $ns_client (CPU $client_cpu) -> $server_ip (Port $port)"

    # Run netperf test:
    #   1. Output netperf table to terminal
    #   2. Append the last result line's throughput value to LOG_FILE for aggregation
    ip netns exec $ns_client taskset -c $client_cpu netperf \
        -H $server_ip -p $port -l $DURATION -t TCP_STREAM \
	-c -C \
        -- -m 64K,64K -M 64K,64K -s 2M,2M -S 2M,2M | tee /dev/tty | tail -n 1 | awk '{print $5}' >> $LOG_FILE &
}

# Cleanup before running (kill any existing netserver processes)
killall netserver > /dev/null 2>&1

echo ">>> Starting $NUM_PAIRS Servers..."
for ((i=0; i<NUM_PAIRS; i++)); do
    start_server $((NUM_VFs - 1 - i))
done

sleep 2

echo ">>> Benchmark starting (Duration: $DURATION s)..."
echo "-----------------------------------------------------------"

# Launch all client-server pairs in parallel
for ((i=0; i<NUM_PAIRS; i++)); do
    start_client $i $((NUM_VFs - 1 - i))
done

# Wait for all netperf clients to finish
wait

echo -e "\n-----------------------------------------------------------"

# --- AGGREGATED REPORTING ---
# If log file has data, calculate total and average throughput
if [ -s $LOG_FILE ]; then
    TOTAL_BW=$(awk '{sum+=$1} END {printf "%.2f", sum}' $LOG_FILE)
    AVG_BW=$(awk '{sum+=$1} END {printf "%.2f", sum/NR}' $LOG_FILE)

    echo -e "BENCHMARK RESULT FOR $NUM_VFs VFs:"
    echo -e "Total Aggregated Throughput: \033[1;32m$TOTAL_BW 10^6bits/s\033[0m"
    echo -e "Approximate: \033[1;32m$(echo "scale=2; $TOTAL_BW/1000" | bc) Gbps\033[0m"
    echo -e "Average per Pair: $(echo "scale=2; $AVG_BW/1000" | bc) Gbps"
else
    echo "Error: No data collected in $LOG_FILE"
fi
echo "-----------------------------------------------------------"

# Cleanup after running (kill any remaining netserver processes)
killall netserver > /dev/null 2>&1
echo ">>> Cleaned up netservers."
