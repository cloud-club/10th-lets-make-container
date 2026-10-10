# 5주차 - 컨테이너 네트워크

## 1. 네트워크 격리와 연결

network namespace를 만들면 인터페이스, IP, 라우팅 테이블, 포트 등을 나눌 수 있다. 분리 직후에는 loopback만 있으므로 외부 통신 경로를 따로 만들어야 한다.

| 구성 | 역할 |
| --- | --- |
| veth pair | 양 끝이 연결된 가상 인터페이스 |
| bridge | 호스트에서 여러 인터페이스를 연결하는 가상 스위치 |
| route | 목적지까지 보낼 다음 경로 선택 |
| IP forwarding | 호스트가 다른 네트워크로 패킷 전달 |
| MASQUERADE | 외부로 나가는 출발지 IP를 호스트 인터페이스 주소로 변환 |
| DNS | 이름을 IP 주소로 변환 |

Docker의 기본 bridge 네트워크도 이 기능들을 조합한다. `docker0`은 bridge이고, 컨테이너의 인터페이스는 veth를 통해 연결된다.

## 2. namespace와 호스트 연결

실습 VM에서 `10.200.0.0/24`가 기존 경로와 겹치지 않고, 아래 이름의 장치와 namespace가 없는지 확인한다. 호스트 터미널 A는 정리할 때까지 유지한다.

```bash
ip route
ip netns list
ip link
forward_before=$(sysctl -n net.ipv4.ip_forward)
uplink=$(ip -4 route show default | awk 'NR==1 {print $5}')
echo "$uplink"
sudo cp -p tmproot/etc/resolv.conf tmproot/etc/resolv.conf.week05-backup
```

`uplink`가 VM의 외부 인터페이스인지 확인한다. DNS 백업 파일이 이미 있다면 덮어쓰지 말고 이전 실습 상태부터 확인한다.

```bash
sudo ip netns add ns-study
sudo ip -n ns-study addr
sudo ip -n ns-study link set lo up

sudo ip link add br-study type bridge
sudo ip addr add 10.200.0.1/24 dev br-study
sudo ip link set br-study up

sudo ip link add veth-host type veth peer name veth-ns
sudo ip link set veth-host master br-study
sudo ip link set veth-host up
sudo ip link set veth-ns netns ns-study
sudo ip -n ns-study link set veth-ns name eth0
sudo ip -n ns-study addr add 10.200.0.2/24 dev eth0
sudo ip -n ns-study link set eth0 up
```

호스트 쪽 주소는 bridge에, 내부 주소는 namespace의 `eth0`에 설정한다. 터미널 B에서 셸을 실행한다.

```bash
sudo ip netns exec ns-study chroot tmproot /bin/sh
```

내부에서 `ip addr`, `ip route`, `ping -c 1 10.200.0.1`을 확인한다. 이 단계에서는 같은 subnet의 호스트까지 연결되고 외부로 가는 기본 경로는 없다. 이 명령은 network namespace와 rootfs를 적용할 뿐 PID namespace까지 분리하지는 않는다.

## 3. 외부 통신과 HTTP 서버

### 아웃바운드

터미널 A에서 기본 경로와 전달 규칙을 설정한다. 아래 규칙은 한 번만 추가한다.

```bash
sudo ip -n ns-study route add default via 10.200.0.1
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -I FORWARD -i br-study -o "$uplink" -j ACCEPT
sudo iptables -I FORWARD -i "$uplink" -o br-study \
  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -t nat -A POSTROUTING -s 10.200.0.0/24 \
  -o "$uplink" -j MASQUERADE
```

내부의 패킷은 `eth0`에서 veth와 bridge를 거쳐 호스트로 간다. 호스트는 라우팅과 forwarding으로 외부 인터페이스에 전달하고, MASQUERADE는 출발지 주소를 바꾼다. 응답은 연결 추적 정보를 통해 내부 주소로 되돌아온다.

터미널 B의 셸에서 IP 통신과 이름 해석을 따로 확인한다.

```sh
ping -c 1 1.1.1.1
printf 'nameserver 1.1.1.1\n' > /etc/resolv.conf
wget -O- http://example.com
```

IP로는 되는데 이름으로 실패하면 DNS 설정을 먼저 본다. 반대로 ping 실패만으로 전체 통신 실패를 단정하지는 않는다. 경로나 방화벽에서 ICMP만 차단할 수도 있다.

### 호스트에서 내부 웹 서버 접근

터미널 B의 셸에서 실행한다.

```sh
mkdir -p /www
echo 'hello world' > /www/index.html
httpd -f -p 0.0.0.0:80 -h /www
```

터미널 A에서 요청한다.

```bash
curl http://10.200.0.2
```

호스트는 bridge를 통해 직접 접근할 수 있어 DNAT가 필요 없다. VM 외부에서 호스트의 특정 포트로 접근시키려면 DNAT와 전달 허용 등 추가 구성이 필요하다.

### 정리

터미널 B에서 `Ctrl-C`로 서버를 멈추고 `exit`으로 셸을 종료한다. 터미널 A에서 이번에 추가한 규칙과 장치만 제거한다.

```bash
sudo iptables -t nat -D POSTROUTING -s 10.200.0.0/24 -o "$uplink" -j MASQUERADE
sudo iptables -D FORWARD -i br-study -o "$uplink" -j ACCEPT
sudo iptables -D FORWARD -i "$uplink" -o br-study \
  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo ip netns pids ns-study
```

남은 PID가 없을 때 이어서 정리한다. 프로세스가 남아 있으면 해당 실습 프로세스를 종료한 뒤 진행한다.

```bash
sudo ip netns del ns-study
sudo ip link del br-study
sudo sysctl -w net.ipv4.ip_forward="$forward_before"
sudo mv tmproot/etc/resolv.conf.week05-backup tmproot/etc/resolv.conf
ip netns list
ip link
```

## 4. 심화 질문

### Q1. 각 기능은 패킷 경로에서 어떤 역할을 할까?

namespace는 네트워크 공간을 나누고, veth는 그 경계를 연결한다. bridge는 같은 L2 네트워크의 인터페이스를 연결한다. route와 forwarding이 다른 네트워크로 전달하며, NAT는 주소를 변환한다. 어느 하나만으로 전체 경로가 완성되는 것은 아니다.

### Q2. NAT만 제거하면 어떻게 될까?

호스트와 `10.200.0.2` 사이의 직접 통신은 유지된다. 일반적인 실습 구성에서는 외부가 `10.200.0.0/24`로 돌아오는 경로를 모르므로 외부 왕복 통신이 실패한다. 상위 네트워크에 반환 경로를 설정한 환경이라면 NAT 없이 라우팅으로 통신할 수도 있다.

### Q3. VM 외부에서는 왜 추가 설정이 필요할까?

외부 장비에는 보통 내부 bridge 대역으로 가는 경로가 없다. 호스트 포트를 DNAT로 내부 서버에 전달하거나, 내부 대역까지의 라우팅을 구성해야 한다. 어느 방식이든 방화벽 허용도 필요하다.

### Q4. 127.0.0.1과 0.0.0.0에 listen하는 차이는?

내부의 `127.0.0.1`은 그 namespace의 loopback이다. 여기에만 바인딩하면 호스트가 `10.200.0.2`로 보내는 요청은 받지 못한다. `0.0.0.0`은 해당 namespace의 모든 IPv4 인터페이스에서 받으므로 eth0로 온 요청도 받을 수 있다.

## 5. 정리

네트워크 격리와 통신 연결은 반대 작업이 아니다. 먼저 공간을 나눈 뒤 필요한 경로만 연결한다. 통신이 안 될 때는 인터페이스, 주소, route, forwarding, 방화벽, NAT, DNS 순으로 확인할 수 있다.
