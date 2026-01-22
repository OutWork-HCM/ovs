#!/bin/bash
# Description: Parallel Benchmark based on NUM_VFs

# --- Variables ---
NUM_VFs=4          # Bạn có thể thay đổi số này (2, 4, 8, 16...)
DURATION=60        
IP_BASE="192.168.50"
NS_PREFIX="ns"

# Tính toán số lượng cặp
NUM_PAIRS=$((NUM_VFs / 2))

# Hàm chạy server iperf3
function start_server() {
    local s_idx=$1
    local ns_server="${NS_PREFIX}${s_idx}"
    # Chạy server và thoát sau 1 session (-1)
    ip netns exec $ns_server iperf3 -s -1 > /dev/null 2>&1 &
}

# Hàm chạy client iperf3
function start_client() {
    local c_idx=$1
    local s_idx=$2
    local ns_client="${NS_PREFIX}${c_idx}"
    local server_ip="${IP_BASE}.$(($s_idx + 10))"

    echo "Pairing: $ns_client -> $ns_server ($server_ip)"
    ip netns exec $ns_client iperf3 -c $server_ip -t $DURATION &
}

echo ">>> Preparation: Starting $NUM_PAIRS Servers..."
# Server sẽ nằm ở nửa sau của dải VFs: ví dụ NUM_VFs=4 thì server là ns2, ns3
for ((i=0; i<NUM_PAIRS; i++)); do
    s_idx=$((NUM_VFs - 1 - i))
    start_server $s_idx
done

sleep 2 

echo ">>> Benchmark: Starting $NUM_PAIRS Clients simultaneously..."
echo "-----------------------------------------------------------"

# [BẮT ĐẦU ĐO CPU]
sar 1 $((DURATION - 10)) | grep "Average" | awk '{print "\n[RESULT] Average CPU Idle: "$8"%"}' &

# [KÍCH HOẠT CÁC CẶP]
# Client sẽ nằm ở nửa đầu: ns0, ns1... kết nối tới ns(N-1), ns(N-2)...
for ((i=0; i<NUM_PAIRS; i++)); do
    c_idx=$i
    s_idx=$((NUM_VFs - 1 - i))
    start_client $c_idx $s_idx
done

# Chờ tất cả hoàn thành
wait

echo "-----------------------------------------------------------"
echo ">>> Finished testing with $NUM_VFs VFs ($NUM_PAIRS pairs)."
