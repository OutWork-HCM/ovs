#!/bin/bash
# Description: Parallel Benchmark based on NUM_VFs using netperf

# --- Variables ---
NUM_VFs=4          
DURATION=60        
IP_BASE="192.168.50"
NS_PREFIX="ns"
CONFIDENCE="-I 99,2.5" # Thêm tham số tin cậy như bạn đã hỏi ở trên

# Tính toán số lượng cặp
NUM_PAIRS=$((NUM_VFs / 2))

# Hàm chạy server netperf (netserver)
function start_server() {
    local s_idx=$1
    local ns_server="${NS_PREFIX}${s_idx}"
    # netserver mặc định chạy dưới dạng daemon. 
    # Chúng ta chạy nó trong namespace.
    ip netns exec $ns_server netserver > /dev/null 2>&1
}

# Hàm chạy client netperf
function start_client() {
    local c_idx=$1
    local s_idx=$2
    local ns_client="${NS_PREFIX}${c_idx}"
    local server_ip="${IP_BASE}.$(($s_idx + 10))"

    echo "Pairing: $ns_client -> $ns_server ($server_ip)"
    # Cấu trúc: netperf [options] -- [test specific options]
    # -H: Host, -l: length (thời gian), -t: loại test
    ip netns exec $ns_client netperf -H $server_ip -l $DURATION -t TCP_STREAM -c -C $CONFIDENCE &
}

# Dọn dẹp các netserver cũ nếu còn sót lại
killall netserver > /dev/null 2>&1

echo ">>> Preparation: Starting $NUM_PAIRS Servers..."
for ((i=0; i<NUM_PAIRS; i++)); do
    s_idx=$((NUM_VFs - 1 - i))
    start_server $s_idx
done

sleep 2 

echo ">>> Benchmark: Starting $NUM_PAIRS Clients simultaneously..."
echo "-----------------------------------------------------------"

# [BẮT ĐẦU ĐO CPU]
# Sử dụng sar để theo dõi CPU như script cũ
# sar 1 $((DURATION - 5)) | grep "Average" | awk '{print "\n[RESULT] Average CPU Idle: "$8"%"}' &

# [KÍCH HOẠT CÁC CẶP]
for ((i=0; i<NUM_PAIRS; i++)); do
    c_idx=$i
    s_idx=$((NUM_VFs - 1 - i))
    start_client $c_idx $s_idx
done

# Chờ tất cả các tiến trình netperf con hoàn thành
wait

echo "-----------------------------------------------------------"
echo ">>> Finished testing with $NUM_VFs VFs ($NUM_PAIRS pairs)."

# Dọn dẹp netserver sau khi test xong
killall netserver
echo ">>> Cleaned up netservers."
