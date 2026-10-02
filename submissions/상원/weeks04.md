# week 04 제출용


## 정리
cgroup?

cgroup = 프로세스들을 계층적인 그룹으로 묶고, 그 그룹 단위로 CPU/메모리/IO 같은 자원을 제한·분배·관찰하는 리눅스 커널 기능

그래서 지난번 namespace 는 묶는 것 까지만 그룹핑만 했고 이번엔 자원까지 그룹핑


2번 제한이 없다 보니 시스템이 쓸 수 있는 것 다 쓰는 기분?

## 1. pivot_root 후 이전 루트를 put_old에서 분리하는 이유는 무엇일까?
기존 호스트 rootfs에 다시 접근하지 못하게 하기 위해서

## 2.namespace와 cgroup은 각각 어떤 문제를 해결할까? namespace만 만들고 cgroup을 만들지 않으면 부하가 큰 프로세스에서 무엇이 달라질까?
namespace는 격리 프로세스 목록 같은 것은 격리가 되게 할 수 있음 , cgroup은 자원 제한 mem ,cpu 같은 것을 분리

## 3.rootfs·namespace·cgroup을 사람이 순서대로 설정하는 대신 runtime이 처리하려면 부모와 자식 프로세스가 각각 어떤 일을 맡아야 할까?
부모 프로세스는 컨테이너 실행 전에 필요한 환경을 준비한다. namespace와 cgroup을 생성하고 CPU·메모리 제한 값을 설정하며, 자식 프로세스가 사용할 rootfs (사용할 것을 묶는 작업) 도 준비한다.
자식 프로세스는 생성된 namespace 안에서 mount 설정을 수행하고, pivot_root를 통해 준비된 rootfs를 자신의 새로운 /로 전환한다. 이후 이전 rootfs를 분리하고 /proc에 procfs를 마운트한 뒤, 자신을 cgroup에 등록한다. 마지막으로 exec를 통해 실제 컨테이너에서 실행할 명령이나 애플리케이션으로 프로세스를 교체한다.
즉, 부모는 컨테이너 실행 환경을 준비하고 자식은 그 환경 안에서 rootfs와 mount 구성을 완성한 뒤 실제 프로그램을 실행하는 역할을 맡는다.

## 4. 3주차의 스크립트에서 pivot_root와 이전 루트 정리까지 수행하도록 추가하여 제출해주세요. rootfs와 실행할 명령을 인자로 받으면 됩니다. 예: sudo ./makecontainer.sh /home/ubuntu/tmproot /bin/sh

```sh
#!/bin/bash

ROOTFS=$1
CMD=${2:-/bin/sh}

if [ -z "$ROOTFS" ]; then
  echo "Usage: $0 <rootfs> [command]"
  exit 1
fi

sudo unshare \
  --uts \
  --pid \
  --fork \
  --mount \
  bash -c "
    set -e

    # mount 변경이 호스트로 전파되지 않도록 설정
    mount --make-rprivate /

    # 컨테이너용 hostname 설정
    hostname week4

    # rootfs를 pivot_root 가능한 mount point로 만듦
    mount --bind \"$ROOTFS\" \"$ROOTFS\"

    # 이전 루트를 잠시 둘 디렉터리 준비
    mkdir -p \"$ROOTFS/put_old\"

    # 새 rootfs로 이동
    cd \"$ROOTFS\"

    # 현재 디렉터리를 새 /로 만들고,
    # 기존 /는 /put_old로 이동
    pivot_root . put_old

    # 새 root 기준으로 작업 위치 변경
    cd /

    # 기존 호스트 root 분리
    umount -l /put_old
    rmdir /put_old

    # 새 rootfs 기준 procfs 연결
    mkdir -p /proc
    mount -t proc proc /proc

    echo \"===== container info =====\"
    echo \"PID: \$\$ \"
    echo \"Hostname: \$(hostname)\"
    echo \"Root filesystem:\"
    ls /

    echo \"==========================\"

    # 실제 컨테이너 명령 실행
    exec $CMD
  "
  ```