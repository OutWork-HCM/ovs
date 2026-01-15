# 2026-01-09
### Server Information Report

```yaml
OS: Linux Mint 21.3 x86_64 
Host: Z690M AORUS ELITE DDR4 -CF 
Kernel: 6.5.0-14-generic 
CPU: 13th Gen Intel i9-13900K (32) @ 5.800GHz 
Memory: 128572MiB
```

###  HPE - Mellanox ConnectX-4 LX
```yaml
linux@tester03:~$ sudo ethtool -i enp1s0f0np0 
driver: mlx5_core
version: 24.10-3.2.5
firmware-version: 14.32.1010 (HP_2420110034)
expansion-rom-version: 
bus-info: 0000:01:00.0
supports-statistics: yes
supports-test: yes
supports-eeprom-access: no
supports-register-dump: no
supports-priv-flags: yes
```

### Ovswitch
```yaml
linux@tester03:~$ ovs-vsctl --version
ovs-vsctl (Open vSwitch) 2.17.7

linux@tester03:~$ dpkg -l iproute2
Desired=Unknown/Install/Remove/Purge/Hold
| Status=Not/Inst/Conf-files/Unpacked/halF-conf/Half-inst/trig-aWait/Trig-pend
|/ Err?=(none)/Reinst-required (Status,Err: uppercase=bad)
||/ Name           Version         Architecture Description
+++-==============-===============-============-====================================
ii  iproute2       5.15.0-1ubuntu2 amd64        networking and traffic control tools
```

### Procedure to Reproduce
1. Swith to "root" user
```bash
sudo -i
```

2. Check ovs bridge, if exists delete it
```yaml
root@tester03:~# ovs-vsctl show
32549dde-d67b-430c-b183-980a32143c8f
    Bridge br0
        Port enp1s0f0npf0vf0
            Interface enp1s0f0npf0vf0
                error: "could not open network device enp1s0f0npf0vf0 (No such device)"
        Port enp1s0f1npf1vf0
            Interface enp1s0f1npf1vf0
                error: "could not open network device enp1s0f1npf1vf0 (No such device)"
        Port br0
            Interface br0
                type: internal
    ovs_version: "2.17.9"
root@tester03:~# ovs-vsctl del-port br0 enp1s0f0npf0vf0
root@tester03:~# ovs-vsctl del-port br0 enp1s0f1npf1vf0
root@tester03:~# ovs-vsctl show
32549dde-d67b-430c-b183-980a32143c8f
    Bridge br0
        Port br0
            Interface br0
                type: internal
    ovs_version: "2.17.9"
root@tester03:~# ovs-vsctl del-br br0
root@tester03:~# ovs-vsctl show
32549dde-d67b-430c-b183-980a32143c8f
    ovs_version: "2.17.9"
```

3. Enable tc-offload on both interfaces
```yaml
root@tester03:~# ethtool -K enp1s0f0np0 hw-tc-offload on
root@tester03:~# ethtool -K enp1s0f1np1 hw-tc-offload on
root@tester03:~# ethtool -k enp1s0f0np0 | grep hw-tc-offload
hw-tc-offload: on
root@tester03:~# ethtool -k enp1s0f1np1 | grep hw-tc-offload
hw-tc-offload: only on
```

4. Set VF on both interfaces
```yaml
root@tester03:~# echo 1 > /sys/class/net/enp1s0f0np0/device/sriov_numvfs 
root@tester03:~# echo 1 > /sys/class/net/enp1s0f1np1/device/sriov_numvfs
```

5. "switchdev" Configuration
```yaml
root@tester03:~# lspci | grep Mellanox
01:00.0 Ethernet controller: Mellanox Technologies MT27710 Family [ConnectX-4 Lx]
01:00.1 Ethernet controller: Mellanox Technologies MT27710 Family [ConnectX-4 Lx]
01:00.2 Ethernet controller: Mellanox Technologies MT27710 Family [ConnectX-4 Lx Virtual Function]
01:01.2 Ethernet controller: Mellanox Technologies MT27710 Family [ConnectX-4 Lx Virtual Function]
root@tester03:~# echo 0000:01:00.2 > /sys/bus/pci/drivers/mlx5_
mlx5_core/ mlx5_ib/   
root@tester03:~# echo 0000:01:00.2 > /sys/bus/pci/drivers/mlx5_core/unbind 
root@tester03:~# echo 0000:01:01.2 > /sys/bus/pci/drivers/mlx5_core/unbind 
root@tester03:~# devlink dev eswitch set pci/0000:01:00.0 mode switchdev
root@tester03:~# devlink dev eswitch set pci/0000:01:00.1 mode switchdev
root@tester03:~# ip -d link show enp
enp1s0f0np0      enp1s0f0npf0vf0  enp1s0f1np1      enp1s0f1npf1vf0  enp4s0           
root@tester03:~# ip -d link show enp1s0f0np0 
2: enp1s0f0np0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000
    link/ether 94:40:c9:c3:67:fa brd ff:ff:ff:ff:ff:ff promiscuity 0 minmtu 68 maxmtu 9978 addrgenmode none numtxqueues 256 numrxqueues 32 gso_max_size 65536 gso_max_segs 65535 portname p0 switchid fa67c3ffffc94094 parentbus pci parentdev 0000:01:00.0 
    vf 0     link/ether 00:00:00:00:00:00 brd ff:ff:ff:ff:ff:ff, spoof checking off, link-state disable, trust off, query_rss off
root@tester03:~# ip -d link show enp1s0f0npf0vf0 
13: enp1s0f0npf0vf0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000
    link/ether 32:4c:db:2a:0b:74 brd ff:ff:ff:ff:ff:ff promiscuity 0 minmtu 68 maxmtu 9978 addrgenmode none numtxqueues 32 numrxqueues 32 gso_max_size 65536 gso_max_segs 65535 portname pf0vf0 switchid fa67c3ffffc94094 parentbus pci parentdev 0000:01:00.0 
root@tester03:~# ip -d link show enp1s0f1npf1vf0 
14: enp1s0f1npf1vf0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000
    link/ether d6:d2:15:04:7e:85 brd ff:ff:ff:ff:ff:ff promiscuity 0 minmtu 68 maxmtu 9978 addrgenmode none numtxqueues 32 numrxqueues 32 gso_max_size 65536 gso_max_segs 65535 portname pf1vf0 switchid fa67c3ffffc94094 parentbus pci parentdev 0000:01:00.1 
root@tester03:~# echo 0000:01:00.2 > /sys/bus/pci/drivers/mlx5_core/bind 
root@tester03:~# echo 0000:01:01.2 > /sys/bus/pci/drivers/mlx5_core/bind
```

6. Open vSwitch Configuration
- Run openswitch services
```bash
systemctl start openvswitch-switch
```
- Create ovs bridge (name "ovs-sriov")
```bash
ovs-vsctl add-br ovs-sriov
```
- Enable hw-offload (default is "off")
```bash
ovs-vsctl set Open_vSwitch . other_config:hw-offload=true
sudo ovs-vsctl remove Open_vSwitch . other_config tc-policy
ovs-vsctl set Open_vSwitch . other_config:max-idle=30000
ovs-vsctl set Open_vSwitch . other_config:max-revalidator=10000
ovs-vsctl set Open_vSwitch . other_config:n-handler-threads=4
ovs-vsctl set Open_vSwitch . other_config:n-revalidator-threads=4
```
- Restart the ovs service
```bash
systemctl restart openvswitch-switch
```
- Verify hw-offload is enabled
```yaml
root@tester03:~# ovs-vsctl get Open_vSwitch . other_config
{hw-offload="true", n-handler-threads="5", n-revalidator-threads="2"}
```
- Add the PF and the VF representor netdevices as OVS ports
```bash
ovs-vsctl add-port ovs-sriov enp1s0f0np0
ovs-vsctl add-port ovs-sriov enp1s0f0npf0vf0
ovs-vsctl add-port ovs-sriov enp1s0f1npf1vf0
```
- Make sure to bring up the PF and representor netdevices:
```bash
ip link set enp1s0f0np0 up
ip link set enp1s0f0npf0vf0 up
ip link set enp1s0f1npf1vf0 up
```
- Verify the OVS bridge and ports
```yaml
root@tester03:~# ovs-vsctl show
32549dde-d67b-430c-b183-980a32143c8f
    Bridge ovs-sriov
        Port enp1s0f0npf0vf0
            Interface enp1s0f0npf0vf0
        Port enp1s0f1np1
            Interface enp1s0f1np1
        Port ovs-sriov
            Interface ovs-sriov
                type: internal
        Port enp1s0f0np0
            Interface enp1s0f0np0
        Port enp1s0f1npf1vf0
            Interface enp1s0f1npf1vf0
    ovs_version: "2.17.9"
```

7. Test connectivity between VFs
```bash
ip netns add ns0
ip netns add ns1
ip link set enp1s0f0v0 netns ns0
ip link set enp1s0f1v0 netns ns1
ip netns exec ns0 ip addr add 192.168.50.10/24 dev enp1s0f0v0
ip netns exec ns1 ip addr add 192.168.50.20/24 dev enp1s0f1v0
ip netns exec ns0 ip link set enp1s0f0v0 up
ip netns exec ns1 ip link set enp1s0f1v0 up
```

- Check IPv4 information
```yaml
root@tester03:~# ip netns exec ns1 ip a
1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
16: enp1s0f1v0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 7a:77:ee:80:f0:c5 brd ff:ff:ff:ff:ff:ff permaddr a6:93:92:e3:9f:eb
    inet 192.168.50.20/24 scope global enp1s0f1v0
       valid_lft forever preferred_lft forever
    inet6 fe80::7877:eeff:fe80:f0c5/64 scope link 
       valid_lft forever preferred_lft forever
root@tester03:~# ip netns exec ns0 ip a
1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
15: enp1s0f0v0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 9e:f3:7d:50:bb:1b brd ff:ff:ff:ff:ff:ff permaddr 42:29:db:a4:d8:6e
    inet 192.168.50.10/24 scope global enp1s0f0v0
       valid_lft forever preferred_lft forever
    inet6 fe80::9cf3:7dff:fe50:bb1b/64 scope link 
       valid_lft forever preferred_lft forever
```

- Ping test between VFs
```yaml
root@tester03:~# ip netns exec ns0 ping -c 20 192.168.50.20
root@tester03:~# ovs-appctl dpctl/dump-flows -m type=tc
ufid:4604eb2c-a736-4e38-8a9a-b98c0a2b6619, skb_priority(0/0),skb_mark(0/0),ct_state(0/0),ct_zone(0/0),ct_mark(0/0),ct_label(0/0),recirc_id(0),dp_hash(0/0),in_port(enp1s0f0npf0vf0),packet_type(ns=0/0,id=0/0),eth(src=9e:f3:7d:50:bb:1b,dst=3a:fb:88:a5:c4:5d),eth_type(0x0800),ipv4(src=0.0.0.0/0.0.0.0,dst=0.0.0.0/0.0.0.0,proto=0/0,tos=0/0,ttl=0/0,frag=no), packets:19, bytes:1596, used:2.820s, dp:tc, actions:enp1s0f1npf1vf0
ufid:16ff3d2b-5e4a-4781-9413-9c98f76f185f, skb_priority(0/0),skb_mark(0/0),ct_state(0/0),ct_zone(0/0),ct_mark(0/0),ct_label(0/0),recirc_id(0),dp_hash(0/0),in_port(enp1s0f0npf0vf0),packet_type(ns=0/0,id=0/0),eth(src=9e:f3:7d:50:bb:1b,dst=3a:fb:88:a5:c4:5d),eth_type(0x0806),arp(sip=0.0.0.0/0.0.0.0,tip=0.0.0.0/0.0.0.0,op=0/0,sha=00:00:00:00:00:00/00:00:00:00:00:00,tha=00:00:00:00:00:00/00:00:00:00:00:00), packets:1, bytes:46, used:never, dp:tc, actions:enp1s0f1npf1vf0
ufid:cb941e4c-f61b-4770-bda1-47e9dc2e1330, skb_priority(0/0),skb_mark(0/0),ct_state(0/0),ct_zone(0/0),ct_mark(0/0),ct_label(0/0),recirc_id(0),dp_hash(0/0),in_port(enp1s0f0np0),packet_type(ns=0/0,id=0/0),eth(src=94:40:c9:c3:67:fb,dst=33:33:00:00:00:16),eth_type(0x86dd),ipv6(src=::/::,dst=::/::,label=0/0,proto=0/0,tclass=0/0,hlimit=0/0,frag=no), packets:4, bytes:384, used:26.120s, dp:tc, actions:enp1s0f0npf0vf0,enp1s0f1npf1vf0,ovs-sriov
ufid:7c937fe0-dcea-4d1f-834e-57cb8b50c7d1, skb_priority(0/0),skb_mark(0/0),ct_state(0/0),ct_zone(0/0),ct_mark(0/0),ct_label(0/0),recirc_id(0),dp_hash(0/0),in_port(enp1s0f0np0),packet_type(ns=0/0,id=0/0),eth(src=94:40:c9:c3:67:fb,dst=33:33:ff:85:68:0e),eth_type(0x86dd),ipv6(src=::/::,dst=::/::,label=0/0,proto=0/0,tclass=0/0,hlimit=0/0,frag=no), packets:0, bytes:0, used:never, dp:tc, actions:enp1s0f0npf0vf0,enp1s0f1npf1vf0,ovs-sriov
ufid:b99aa419-5c46-4c1a-9d6c-849661c59320, skb_priority(0/0),skb_mark(0/0),ct_state(0/0),ct_zone(0/0),ct_mark(0/0),ct_label(0/0),recirc_id(0),dp_hash(0/0),in_port(enp1s0f0np0),packet_type(ns=0/0,id=0/0),eth(src=94:40:c9:c3:67:fb,dst=33:33:00:00:00:02),eth_type(0x86dd),ipv6(src=::/::,dst=::/::,label=0/0,proto=0/0,tclass=0/0,hlimit=0/0,frag=no), packets:6, bytes:288, used:14.180s, dp:tc, actions:enp1s0f0npf0vf0,enp1s0f1npf1vf0,ovs-sriov
ufid:2eb21eca-7a76-4cf2-bebd-459590d21258, skb_priority(0/0),skb_mark(0/0),ct_state(0/0),ct_zone(0/0),ct_mark(0/0),ct_label(0/0),recirc_id(0),dp_hash(0/0),in_port(enp1s0f0np0),packet_type(ns=0/0,id=0/0),eth(src=94:40:c9:c3:67:fb,dst=33:33:00:00:00:fb),eth_type(0x86dd),ipv6(src=::/::,dst=::/::,label=0/0,proto=0/0,tclass=0/0,hlimit=0/0,frag=no), packets:10, bytes:1215, used:12.730s, dp:tc, actions:enp1s0f0npf0vf0,enp1s0f1npf1vf0,ovs-sriov
ufid:2e616145-e243-4d08-b0bb-02dbdb870857, skb_priority(0/0),skb_mark(0/0),ct_state(0/0),ct_zone(0/0),ct_mark(0/0),ct_label(0/0),recirc_id(0),dp_hash(0/0),in_port(enp1s0f0np0),packet_type(ns=0/0,id=0/0),eth(src=94:40:c9:c3:67:fb,dst=ff:ff:ff:ff:ff:ff),eth_type(0x0800),ipv4(src=0.0.0.0/0.0.0.0,dst=0.0.0.0/0.0.0.0,proto=0/0,tos=0/0,ttl=0/0,frag=no), packets:8, bytes:2512, used:12.700s, dp:tc, actions:enp1s0f0npf0vf0,enp1s0f1npf1vf0,ovs-sriov
ufid:04682cbb-cb41-4082-b446-773f3e563607, skb_priority(0/0),skb_mark(0/0),ct_state(0/0),ct_zone(0/0),ct_mark(0/0),ct_label(0/0),recirc_id(0),dp_hash(0/0),in_port(enp1s0f1npf1vf0),packet_type(ns=0/0,id=0/0),eth(src=3a:fb:88:a5:c4:5d,dst=9e:f3:7d:50:bb:1b),eth_type(0x0800),ipv4(src=0.0.0.0/0.0.0.0,dst=0.0.0.0/0.0.0.0,proto=0/0,tos=0/0,ttl=0/0,frag=no), packets:19, bytes:1596, used:2.820s, dp:tc, actions:enp1s0f0npf0vf0
ufid:5a9f8083-62b7-4af9-9174-26cda5348487, skb_priority(0/0),skb_mark(0/0),ct_state(0/0),ct_zone(0/0),ct_mark(0/0),ct_label(0/0),recirc_id(0),dp_hash(0/0),in_port(enp1s0f1npf1vf0),packet_type(ns=0/0,id=0/0),eth(src=3a:fb:88:a5:c4:5d,dst=9e:f3:7d:50:bb:1b),eth_type(0x0806),arp(sip=0.0.0.0/0.0.0.0,tip=0.0.0.0/0.0.0.0,op=0/0,sha=00:00:00:00:00:00/00:00:00:00:00:00,tha=00:00:00:00:00:00/00:00:00:00:00:00), packets:1, bytes:46, used:never, dp:tc, actions:enp1s0f0npf0vf0
```

# 2026-01-10
### iperf3 benchmark - OVS offload on/off Report

```yaml
root@tester03:/home/linux/vinhhuynh# ./bench_offload.sh
>>> Running Benchmark in mode: OFFLOAD ON (dp:tc)
Average CPU Idle: 88,84% 
[SUM]   0.00-30.02  sec  2.60 GBytes   744 Mbits/sec  0.050 ms  219961/43824509 (0.5%)  receiver
------------------------------------------------
>>> Running Benchmark in mode: OFFLOAD OFF (dp:ovs)
Average CPU Idle: 87,29%
[SUM]   0.00-30.02  sec  2.59 GBytes   741 Mbits/sec  0.055 ms  3852641/47316817 (8.1%)  receiver
```

- ***Note***: iperf3 with following command:
```bash
iperf3 -c <server_ip> -u -l 64 -b 0 -t 30 -P 64
```

| Mode      | Throughput (Mbits/sec) | CPU Idle (%) | Packet Loss (%) | Delay (ms) |
|-----------|------------------------|--------------|-----------------|------------|
| OFFLOAD ON| 744                    | 88.84        | 0.5             | 0.050      |
| OFFLOAD OFF| 741                   | 87.29        | 8.1             | 0.055      |
- **Conclusion**: With offload enabled, we achieved slightly higher throughput, significantly lower packet loss, and marginally reduced delay, all while maintaining better CPU idle percentages. This indicates that enabling offload improves overall network performance and efficiency in this setup.

- Some of useful commands to verify OVS offload status and statistics:
```yaml
watch -n 1 "cat /proc/interrupts | grep mlx5"
watch -n 1 "ovs-appctl dpctl/dump-flows -m type=tc"
watch -n 1 "ovs-appctl dpctl/dump-flows -m type=ovs"
ip netns exec ns0 watch -n 1 cat /proc/net/pktgen/enp1s0f0v0
watch -n 1 "ovs-vsctl get Open_vSwitch . other_config"
```

# 2026-01-12
### Bad news - OVS offload with ConnectX-4 LX is not actually working.

After further investigation and testing, it has been determined that the OVS offload feature is not functioning as expected with the Mellanox ConnectX-4 LX network interface cards. Despite enabling hardware offloading in Open vSwitch and configuring the system for switchdev mode, the expected performance improvements and offloading behaviors are not being realized.
We checked with some log files and found the offload function is not activated.
```yaml
root@tester03:~# tc -stats filter show dev enp1s0f1npf1vf0 ingress 
filter protocol ip pref 2 flower chain 0 
filter protocol ip pref 2 flower chain 0 handle 0x1 
  dst_mac 9e:f3:7d:50:bb:1b
  src_mac 7a:77:ee:80:f0:c5
  eth_type ipv4
  ip_flags nofrag
  not_in_hw
        action order 1: mirred (Egress Redirect to device enp1s0f0npf0vf0) stolen
        index 4 ref 1 bind 1 installed 5 sec used 5 sec firstused 5 sec
        Action statistics:
        Sent 3260 bytes 70 pkt (dropped 0, overlimits 0 requeues 0) 
        backlog 0b 0p requeues 0
        cookie 497693cbd8498f9aca704e8b2a9a464d
        no_percpu

filter protocol arp pref 4 flower chain 0 
filter protocol arp pref 4 flower chain 0 handle 0x1 
  dst_mac 9e:f3:7d:50:bb:1b
  src_mac 7a:77:ee:80:f0:c5
  eth_type arp
  not_in_hw
        action order 1: mirred (Egress Redirect to device enp1s0f0npf0vf0) stolen
        index 13 ref 1 bind 1 installed 0 sec used 0 sec
        Action statistics:
        Sent 0 bytes 0 pkt (dropped 0, overlimits 0 requeues 0) 
        backlog 0b 0p requeues 0
        cookie 92b3dd11f24234c8ab0a9ca851531da9
        no_percpu
```

We checked all configurations and verified that the hardware and software settings are correct. However, the offload functionality does not appear to be activated, as indicated by the "not_in_hw" status in the traffic control (tc) filter output.

```yaml
root@tester03:~# ethtool -k enp1s0f1npf1vf0 | grep hw-tc-offload
hw-tc-offload: on
```

```yaml
root@tester03:~# ovs-vsctl get Open_vSwitch . other_config
{hw-offload="true", max-idle="30000", max-revalidator="10000", n-handler-threads="4", n-revalidator-threads="4"}
```

```yaml
root@tester03:~# devlink dev eswitch show pci/0000:01:00.0 
pci/0000:01:00.0: mode switchdev inline-mode link encap-mode basic
```

```yaml
root@tester03:~# ethtool -i enp1s0f0np0
driver: mlx5_core
version: 24.10-3.2.5
firmware-version: 14.32.1010 (HP_2420110034)
expansion-rom-version: 
bus-info: 0000:01:00.0
supports-statistics: yes
supports-test: yes
supports-eeprom-access: no
supports-register-dump: no
supports-priv-flags: yes
```

We will continue to investigate the issue and work towards a solution.

# 2026-01-13
### Follow-up on OVS offload with ConnectX-4 LX

Today, we tried upgrading the firmware and driver of the Mellanox ConnectX-4 LX NICs to see if that would resolve the offload issue. However, after performing the upgrades, we found that the problem persists.

```yaml
linux@tester03:~$ sudo flint -d /dev/mst/mt4117_pciconf0 q full
Image type:            FS3
FW Version:            14.32.1908
FW Release Date:       17.8.2025
Part Number:           817753-B21_Ax
Description:           HPE Ethernet 10/25Gb 2-port 640SFP28 Adapter
Product Version:       14.32.1908
Rom Info:              type=UEFI version=14.25.17 cpu=AMD64
                       type=PXE version=3.6.502 cpu=AMD64
Description:           UID                GuidsNumber
Base GUID:             9440c9ffffc367fa        16
Base MAC:              9440c9c367fa            16
Image VSD:             N/A
Device VSD:            N/A
PSID:                  HP_2420110034
Security Attributes:   N/A
Default Update Method: fw_ctrl
```

Check with on kernel driver version:
```yaml
root@tester03:/home/linux/vinhhuynh# ethtool -i enp1s0f0np0 
driver: mlx5_core
version: 6.5.0-14-generic
firmware-version: 14.32.1908 (HP_2420110034)
expansion-rom-version: 
bus-info: 0000:01:00.0
supports-statistics: yes
supports-test: yes
supports-eeprom-access: no
supports-register-dump: no
supports-priv-flags: yes
```

- Configuration checked
```yaml
root@tester03:/home/linux/vinhhuynh# ethtool -k enp1s0f
enp1s0f0np0      enp1s0f0npf0vf0  enp1s0f1np1      enp1s0f1npf1vf0  
root@tester03:/home/linux/vinhhuynh# ethtool -k enp1s0f1npf1vf0 | grep hw-tc-offload
hw-tc-offload: on
root@tester03:/home/linux/vinhhuynh# ovs-vsctl get Open_vSwitch . other_config
{hw-offload="true", max-idle="30000", max-revalidator="10000", n-handler-threads="4", n-revalidator-threads="4"}
root@tester03:/home/linux/vinhhuynh# devlink dev eswitch show pci/0000:01:00.0
pci/0000:01:00.0: mode switchdev inline-mode link encap-mode basic
```
- tc filter still shows offload is not active
```yaml
root@tester03:~# tc filter show dev enp1s0f1npf1vf0 ingress
filter protocol ip pref 3 flower chain 0 
filter protocol ip pref 3 flower chain 0 handle 0x1 
  dst_mac 9e:f3:7d:50:bb:1b
  src_mac 5e:2a:fd:cc:7e:59
  eth_type ipv4
  ip_flags nofrag
  not_in_hw
        action order 1: mirred (Egress Redirect to device enp1s0f0npf0vf0) stolen
        index 4 ref 1 bind 1
        cookie f14014898849b7c13348c792e546283f
        no_percpu

filter protocol arp pref 4 flower chain 0 
filter protocol arp pref 4 flower chain 0 handle 0x1 
  dst_mac 9e:f3:7d:50:bb:1b
  src_mac 5e:2a:fd:cc:7e:59
  eth_type arp
  not_in_hw
        action order 1: mirred (Egress Redirect to device enp1s0f0npf0vf0) stolen
        index 2 ref 1 bind 1
        cookie 691e42d08f45834b36525f8dfc6b114f
        no_percpu
```

```yaml
root@tester03:~# ovs-appctl dpctl/dump-flows -m type=offloaded

root@tester03:~# ovs-appctl dpctl/dump-flows -m type=non-offloaded

ufid:0d9c0633-8a17-4abb-a965-b8b0af9ee4ed, skb_priority(0/0),skb_mark(0/0),ct_state(0/0),ct_zone(0/0),ct_mark(0/0),ct_label(0/0),recirc_id(0),dp_hash(0/0),in_port(enp1s0f0npf0vf0),packet_type(ns=0/0,id=0/0),eth(src=9e:f3:7d:50:bb:1b,dst=5e:2a:fd:cc:7e:59),eth_type(0x0800),ipv4(src=0.0.0.0/0.0.0.0,dst=0.0.0.0/0.0.0.0,proto=0/0,tos=0/0,ttl=0/0,frag=no), packets:163, bytes:13692, used:0.570s, dp:tc, actions:enp1s0f1npf1vf0
ufid:4a376bec-6d82-4b2e-acab-ff7aa1d069b6, skb_priority(0/0),skb_mark(0/0),ct_state(0/0),ct_zone(0/0),ct_mark(0/0),ct_label(0/0),recirc_id(0),dp_hash(0/0),in_port(enp1s0f0npf0vf0),packet_type(ns=0/0,id=0/0),eth(src=9e:f3:7d:50:bb:1b,dst=5e:2a:fd:cc:7e:59),eth_type(0x0806),arp(sip=0.0.0.0/0.0.0.0,tip=0.0.0.0/0.0.0.0,op=0/0,sha=00:00:00:00:00:00/00:00:00:00:00:00,tha=00:00:00:00:00:00/00:00:00:00:00:00), packets:9, bytes:414, used:1.660s, dp:tc, actions:enp1s0f1npf1vf0
ufid:c442c614-d1a5-4058-b799-06a53eedff5c, skb_priority(0/0),skb_mark(0/0),ct_state(0/0),ct_zone(0/0),ct_mark(0/0),ct_label(0/0),recirc_id(0),dp_hash(0/0),in_port(enp1s0f0np0),packet_type(ns=0/0,id=0/0),eth(src=94:40:c9:c3:67:fb,dst=ff:ff:ff:ff:ff:ff),eth_type(0x0800),ipv4(src=0.0.0.0/0.0.0.0,dst=0.0.0.0/0.0.0.0,proto=0/0,tos=0/0,ttl=0/0,frag=no), packets:8, bytes:2512, used:15.470s, dp:tc, actions:ovs-sriov,enp1s0f0npf0vf0,enp1s0f1npf1vf0
ufid:0fcf6352-9136-476e-9632-9414e332ad57, skb_priority(0/0),skb_mark(0/0),ct_state(0/0),ct_zone(0/0),ct_mark(0/0),ct_label(0/0),recirc_id(0),dp_hash(0/0),in_port(enp1s0f0np0),packet_type(ns=0/0,id=0/0),eth(src=94:40:c9:c3:67:fb,dst=33:33:00:00:00:16),eth_type(0x86dd),ipv6(src=::/::,dst=::/::,label=0/0,proto=0/0,tclass=0/0,hlimit=0/0,frag=no), packets:4, bytes:384, used:28.600s, dp:tc, actions:ovs-sriov,enp1s0f0npf0vf0,enp1s0f1npf1vf0
ufid:ecb99242-585b-4420-8abe-78892d27ddc1, skb_priority(0/0),skb_mark(0/0),ct_state(0/0),ct_zone(0/0),ct_mark(0/0),ct_label(0/0),recirc_id(0),dp_hash(0/0),in_port(enp1s0f0np0),packet_type(ns=0/0,id=0/0),eth(src=94:40:c9:c3:67:fb,dst=33:33:ff:85:68:0e),eth_type(0x86dd),ipv6(src=::/::,dst=::/::,label=0/0,proto=0/0,tclass=0/0,hlimit=0/0,frag=no), packets:0, bytes:0, used:never, dp:tc, actions:ovs-sriov,enp1s0f0npf0vf0,enp1s0f1npf1vf0
ufid:e7b2e3eb-640a-46dd-94b7-5f2212541204, skb_priority(0/0),skb_mark(0/0),ct_state(0/0),ct_zone(0/0),ct_mark(0/0),ct_label(0/0),recirc_id(0),dp_hash(0/0),in_port(enp1s0f0np0),packet_type(ns=0/0,id=0/0),eth(src=94:40:c9:c3:67:fb,dst=33:33:00:00:00:02),eth_type(0x86dd),ipv6(src=::/::,dst=::/::,label=0/0,proto=0/0,tclass=0/0,hlimit=0/0,frag=no), packets:7, bytes:336, used:3.760s, dp:tc, actions:ovs-sriov,enp1s0f0npf0vf0,enp1s0f1npf1vf0
ufid:0d0f558a-1cac-4e9e-b9a7-7e11f27ad9a5, skb_priority(0/0),skb_mark(0/0),ct_state(0/0),ct_zone(0/0),ct_mark(0/0),ct_label(0/0),recirc_id(0),dp_hash(0/0),in_port(enp1s0f0np0),packet_type(ns=0/0,id=0/0),eth(src=94:40:c9:c3:67:fb,dst=33:33:00:00:00:fb),eth_type(0x86dd),ipv6(src=::/::,dst=::/::,label=0/0,proto=0/0,tclass=0/0,hlimit=0/0,frag=no), packets:11, bytes:1308, used:0.090s, dp:tc, actions:ovs-sriov,enp1s0f0npf0vf0,enp1s0f1npf1vf0
ufid:891440f1-c1b7-4988-92c7-48333f2846e5, skb_priority(0/0),skb_mark(0/0),ct_state(0/0),ct_zone(0/0),ct_mark(0/0),ct_label(0/0),recirc_id(0),dp_hash(0/0),in_port(enp1s0f1npf1vf0),packet_type(ns=0/0,id=0/0),eth(src=5e:2a:fd:cc:7e:59,dst=9e:f3:7d:50:bb:1b),eth_type(0x0800),ipv4(src=0.0.0.0/0.0.0.0,dst=0.0.0.0/0.0.0.0,proto=0/0,tos=0/0,ttl=0/0,frag=no), packets:163, bytes:13692, used:0.570s, dp:tc, actions:enp1s0f0npf0vf0
ufid:d0421e69-4b83-458f-8d5f-52364f116bfc, skb_priority(0/0),skb_mark(0/0),ct_state(0/0),ct_zone(0/0),ct_mark(0/0),ct_label(0/0),recirc_id(0),dp_hash(0/0),in_port(enp1s0f1npf1vf0),packet_type(ns=0/0,id=0/0),eth(src=5e:2a:fd:cc:7e:59,dst=9e:f3:7d:50:bb:1b),eth_type(0x0806),arp(sip=0.0.0.0/0.0.0.0,tip=0.0.0.0/0.0.0.0,op=0/0,sha=00:00:00:00:00:00/00:00:00:00:00:00,tha=00:00:00:00:00:00/00:00:00:00:00:00), packets:9, bytes:414, used:1.660s, dp:tc, actions:enp1s0f0npf0vf0
```

Checked with MLNX_OFED version:
```yaml
root@tester03:~# ethtool -i enp1s0f0np0 
driver: mlx5_core
version: 24.10-3.2.5
firmware-version: 14.32.1908 (HP_2420110034)
expansion-rom-version: 
bus-info: 0000:01:00.0
supports-statistics: yes
supports-test: yes
supports-eeprom-access: no
supports-register-dump: no
supports-priv-flags: yes
```

# 2026-01-15
### Next steps on OVS offload with ConnectX-4 LX

Today, we did the following steps to further investigate the OVS offload issue with ConnectX-4 LX:
- Reinstall OS with Linux Mint 21.3 (based on Ubuntu 22.04) edge version with Kernel 6.5.0-14-generic.
- Flash the stock firmware version 14.32.1908 to NIC.
We checked with both drivers - the default kernel driver and MLNX_OFED driver version 24.10-3.2.5 - but the offload issue still persists.

```yaml
flint -d /dev/mst/mt4117_pciconf0 q full
Image type:            FS3
FW Version:            14.32.1908
FW Release Date:       17.8.2025
Part Number:           MCX4121A-ACA_Ax
Description:           ConnectX-4 Lx EN network interface card; 25GbE dual-port SFP28; PCIe3.0 x8; ROHS R6
Product Version:       14.32.1908
Rom Info:              type=UEFI version=14.25.17 cpu=AMD64,AARCH64
                       type=PXE version=3.6.502 cpu=AMD64
Description:           UID                GuidsNumber
Base GUID:             9440c9ffffc367fa        16
Base MAC:              9440c9c367fa            16
Image VSD:             N/A
Device VSD:            N/A
PSID:                  MT_2420110034
Security Attributes:   N/A
Default Update Method: fw_ctrl
```

```yaml
root@tester03:~# ethtool -i enp1s0f0np0 
driver: mlx5_core
version: 24.10-3.2.5
firmware-version: 14.32.1908 (MT_2420110034)
expansion-rom-version: 
bus-info: 0000:01:00.0
supports-statistics: yes
supports-test: yes
supports-eeprom-access: no
supports-register-dump: no
supports-priv-flags: yes
```



