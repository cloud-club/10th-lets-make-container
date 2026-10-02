### pivot_root 후 이전 루트를 put_old에서 분리하는 이유는 무엇일까?
pivot_root : 새 rootfs의 아래의 /put_old로 이동
(실행전에 /.. -> 에서 실행후 (/tmproot), put_old는 <-이전 호스트의 루트파일시스템

- 이전 루트를 분리하지 않으면 기존 호스트파일시스템에도 접근가능
- 따라서 이절 루트를 분리해서 침범을 막는다
umount -l /put_old
rmdir /put_old
불필요한 자원 회수

### namespace와 cgroup은 각각 어떤 문제를 해결할까? namespace만 만들고 cgroup을 만들지 않으면 부하가 큰 프로세스에서 무엇이 달라질까?
namespace : 프로세스가 보는 환경 분리 
(사용자 입장에서 간단화 할수 있음.)

cgroup : 프로세스 자원 관리
-> 특정(부하가 큰) 프로세스가 호스트 or 다른 프로세스에게 영향끼치는걸 제한할수 있음.

  

### rootfs·namespace·cgroup을 사람이 순서대로 설정하는 대신 runtime이 처리하려면 부모와 자식 프로세스가 각각 어떤 일을 맡아야 할까?
부모 : rootfs경로 확인, cgroup(~자식이 일을 실행하기 전)이랑 자원제한 설정, 자식프로세스 상태관리
자식 : 새로운 namespace에서 마운트 설정, pivot_root 실행, 이전 루트 분리후 필요한 /proc만 마운트


부모 프로세스
  ├─ rootfs 및 명령 확인
  ├─ cgroup 생성 및 자원 제한 설정
  ├─ 자식 프로세스 생성
  └─ 자식의 종료 상태 관리
             │
             ▼
자식 프로세스
  ├─ namespace 격리
  ├─ mount 구성 및 rootfs 준비
  ├─ pivot_root 실행
  ├─ 이전 루트 분리
  ├─ procfs 마운트
  └─ 지정된 명령 실행
  
### 3주차의 스크립트에서 pivot_root와 이전 루트 정리까지 수행하도록 추가하여 제출해주세요. 
rootfs와 실행할 명령을 인자로 받으면 됩니다. 예: sudo ./makecontainer.sh /home/ubuntu/tmproot /bin/sh


#!/bin/bash

if [ "$#" -lt 2 ]; then
    echo "사용법: sudo $0 <rootfs 경로> <실행할 명령>"
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "root 권한으로 실행해주세요."
    exit 1
fi

ROOTFS=$(realpath "$1")
shift

if [ ! -x "$ROOTFS/bin/sh" ]; then
    echo "오류: rootfs에 실행 가능한 /bin/sh가 없습니다."
    exit 1
fi

unshare --mount --uts --pid --fork /bin/bash -c '
    set -eu

    ROOTFS=$1
    shift

    # mount 변경이 호스트로 전파되지 않도록 설정
    mount --make-rprivate /

    # pivot_root에 필요한 mount point 준비
    mount --bind "$ROOTFS" "$ROOTFS"
    mkdir -p "$ROOTFS/put_old" "$ROOTFS/proc"

    # 새로운 rootfs로 이동
    cd "$ROOTFS"
    pivot_root . put_old
    cd /

    # 이전 호스트 루트 분리 및 디렉터리 정리
    umount -l /put_old
    rmdir /put_old

    # 새 rootfs의 /proc에 procfs 연결
    mount -t proc proc /proc

    # UTS namespace의 hostname 설정
    hostname week4

    # 지정한 명령 실행
    exec "$@"
' makecontainer "$ROOTFS" "$@"

