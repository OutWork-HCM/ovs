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







