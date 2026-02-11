
# 📘 Cẩm nang lệnh Open vSwitch (OVS)

### 1. Quản lý Bridge & Port (Cấu hình hệ thống)

Sử dụng `ovs-vsctl` để thao tác với cơ sở dữ liệu cấu hình.

| Lệnh | Giải thích |
| --- | --- |
| `ovs-vsctl show` | Hiển thị toàn bộ cấu hình hiện tại (Bridges, Ports, Interfaces). |
| `ovs-vsctl add-br <br>` | Tạo một Bridge mới (Switch ảo). |
| `ovs-vsctl del-br <br>` | Xóa một Bridge. |
| `ovs-vsctl add-port <br> <port>` | Thêm cổng vào Bridge (Vật lý hoặc Representor). |
| `ovs-vsctl del-port <br> <port>` | Xóa cổng khỏi Bridge. |
| `ovs-vsctl list-ports <br>` | Liệt kê danh sách các cổng trong một Bridge. |
| `ovs-vsctl set Port <p> tag=10` | Gán VLAN Tag (Access Port) cho một cổng. |

### 2. Quản lý Luồng dữ liệu (Flow Control)

Sử dụng `ovs-ofctl` để điều khiển gói tin theo giao thức OpenFlow.

| Lệnh | Giải thích |
| --- | --- |
| `ovs-ofctl show <br>` | Xem danh sách cổng kèm theo số Port ID của OVS. |
| `ovs-ofctl dump-flows <br>` | Xem tất cả quy tắc điều hướng gói tin (Flows) đang chạy. |
| `ovs-ofctl add-flow <br> <rule>` | Thêm một quy tắc điều hướng mới. |
| `ovs-ofctl del-flows <br>` | Xóa toàn bộ quy tắc trên Bridge. |

### 3. Kiểm tra & Debug (Trạng thái thực thực tế)

Sử dụng `ovs-appctl` và `ovs-dpctl` để kiểm tra các bảng dữ liệu động.

| Lệnh | Giải thích |
| --- | --- |
| `ovs-appctl fdb/show <br>` | Xem **bảng MAC (FDB)** để biết thiết bị nào ở cổng nào. |
| `ovs-appctl fdb/flush <br>` | Xóa bảng MAC cũ để Switch học lại từ đầu. |
| `ovs-dpctl dump-flows` | Xem flow ở **tầng Kernel** (nơi xử lý gói tin thực tế). |
| `ovs-dpctl-top` | Theo dõi lưu lượng flow theo thời gian thực (giống lệnh `top`). |
| `ovs-tcpdump -i <port>` | Bắt gói tin trực tiếp trên một cổng ảo OVS. |

### 4. Quản lý Database & Offload

Sử dụng để cấu hình các tính năng nâng cao như Hardware Offload.

| Lệnh | Giải thích |
| --- | --- |
| `ovs-vsctl get Open_vSwitch . other_config` | Kiểm tra cấu hình hệ thống (như `hw-offload`). |
| `ovs-vsctl set Open_vSwitch . other_config:hw-offload=true` | **Bật tính năng Hardware Offload**. |
| `ovsdb-tool show-log` | Xem lịch sử thay đổi của cơ sở dữ liệu OVS. |

---

### 💡 Mẹo nhỏ khi làm việc với SR-IOV:

* Luôn đảm bảo các **Representor Ports** trên Host ở trạng thái **UP** bằng lệnh: `ip link set <interface> up`.
* Nếu dùng **Hardware Offload**, hãy kiểm tra thêm lệnh: `ovs-appctl dpctl/dump-flows -m type=tc` để xem các luồng đã xuống phần cứng chưa.

