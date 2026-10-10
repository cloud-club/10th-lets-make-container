# 4주차 - pivot_root와 cgroups v2

## 1. 루트 교체와 자원 제한

`chroot`는 프로세스가 경로를 찾는 기준을 바꾼다. `pivot_root`는 현재 mount namespace의 루트 마운트를 새 rootfs로 교체하고, 이전 루트를 새 루트 아래로 옮긴다. 이후 이전 루트를 분리하는 단계까지 필요하다.

namespace와 cgroup도 역할이 다르다.

- namespace: 프로세스가 보는 자원의 범위를 나눈다.
- cgroup: 프로세스를 그룹으로 묶고 자원 사용량을 제한·측정한다.

PID가 1로 보인다고 메모리나 CPU 사용량에 상한이 생기는 것은 아니다.

## 2. pivot_root 적용

3주차 스크립트의 `chroot` 부분을 루트 교체와 이전 루트 정리로 바꾼다. BusyBox rootfs를 기준으로 다음을 `makecontainer.sh`에 저장한다.

```bash
#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 || $# < 2 )); then
    echo "사용법: sudo $0 ROOTFS COMMAND [ARG...]" >&2
    exit 1
fi
rootfs=$(realpath -e -- "$1")
shift

exec unshare --uts --pid --fork --mount bash -c '
    set -euo pipefail
    rootfs=$1
    shift
    export PATH=/usr/sbin:/usr/bin:/sbin:/bin
    mount --make-rprivate /
    hostname week4
    mount --bind "$rootfs" "$rootfs"
    mkdir "$rootfs/put_old"
    cd "$rootfs"
    pivot_root . put_old
    cd /
    hash -r
    /bin/busybox umount -l /put_old
    /bin/busybox rmdir /put_old
    /bin/busybox mkdir -p /proc
    /bin/busybox mount -t proc proc /proc
    exec "$@"
' makecontainer-init "$rootfs" "$@"
```

`tmproot`에 이전 실습 마운트나 `put_old`가 남아 있지 않은 상태에서 실행한다.

```bash
chmod +x makecontainer.sh
sudo ./makecontainer.sh tmproot /bin/sh
```

새 루트는 mount point여야 하므로 자기 자신에 bind mount한다. `pivot_root . put_old` 직후 이전 호스트 루트가 `/put_old`에 있고, `umount -l` 후에는 그 경로에서 분리된다. `hash -r`은 Bash가 기억하던 이전 명령 경로를 비운다.

내부에서 `ls /`, `hostname`, `echo $$`, `ps`를 확인하고 `exit`으로 종료한다. 호스트에서는 다음으로 남은 마운트를 확인한다.

```bash
findmnt --mountpoint tmproot
findmnt --mountpoint tmproot/proc
```

## 3. cgroup으로 제한하기

아래 부하 실험은 컨테이너 안이 아니라 실습 VM의 호스트에서 진행한다.

```bash
sudo apt-get update
sudo apt-get install -y stress-ng
stat -fc %T /sys/fs/cgroup
cat /sys/fs/cgroup/cgroup.controllers
sudo mkdir /sys/fs/cgroup/test-cgroup
ls /sys/fs/cgroup/test-cgroup/{memory.max,memory.swap.max,cpu.max}
```

파일시스템은 `cgroup2fs`여야 한다. 필요한 설정 파일이 없으면 부하를 실행하지 않고 상위의 `cgroup.subtree_control`과 controller 구성을 확인한다. 기존 system cgroup 설정을 임의로 바꾸지 않는다.

### 메모리

```bash
echo 52428800 | sudo tee /sys/fs/cgroup/test-cgroup/memory.max
echo 0 | sudo tee /sys/fs/cgroup/test-cgroup/memory.swap.max
cat /sys/fs/cgroup/test-cgroup/memory.events

sudo bash -c 'echo $$ > /sys/fs/cgroup/test-cgroup/cgroup.procs
cat /proc/self/cgroup
exec stress-ng --vm 1 --vm-bytes 100M --vm-keep --timeout 20s'

cat /sys/fs/cgroup/test-cgroup/memory.events
```

메모리는 50 MiB, swap은 0으로 설정한다. 새 셸을 먼저 그룹에 넣고 `exec`하므로 부하 프로세스와 이후 자식도 제한을 받는다. 이미 실행 중인 자식까지 자동으로 이동하는 것은 아니다.

부하 전후 `oom`과 `oom_kill`의 차이를 확인한다. 실제 값은 VM에서 측정해야 한다. 한도를 넘는 메모리 요청을 회수로 해결하지 못하면 그룹 안에서 OOM kill이 발생할 수 있다.

Docker의 `--memory 50m --memory-swap 50m`도 비교할 수 있다. 여기서 `--memory-swap`은 메모리와 swap의 합계 상한이므로 두 값이 같으면 swap 허용량은 0이다.

### CPU

먼저 CPU quota가 없는 상태에서 실행하고, 제한을 설정한 뒤 같은 부하를 실행한다.

```bash
cat /sys/fs/cgroup/test-cgroup/cpu.max
sudo bash -c 'echo $$ > /sys/fs/cgroup/test-cgroup/cgroup.procs
exec stress-ng --cpu 1 --timeout 20s'

echo '50000 100000' | sudo tee /sys/fs/cgroup/test-cgroup/cpu.max
cat /sys/fs/cgroup/test-cgroup/cpu.stat
sudo bash -c 'echo $$ > /sys/fs/cgroup/test-cgroup/cgroup.procs
exec stress-ng --cpu 1 --timeout 20s'
cat /sys/fs/cgroup/test-cgroup/cpu.stat
```

`50000 100000`은 100ms 주기마다 그룹 전체에 CPU 시간 50ms를 허용한다. 여러 코어를 가진 VM 전체의 50%가 아니라 CPU 한 개의 절반에 해당하는 시간 예산이다.

`nr_throttled`, `throttled_usec`의 증가량으로 제한 흔적을 확인한다. 메모리 OOM과 달리 CPU quota는 보통 프로세스를 죽이지 않고 다음 주기까지 실행을 늦춘다.

부하가 끝나고 `cgroup.procs`가 비었을 때 정리한다.

```bash
cat /sys/fs/cgroup/test-cgroup/cgroup.procs
sudo rmdir /sys/fs/cgroup/test-cgroup
```

## 4. 심화 질문

### Q1. 이전 루트를 put_old에서 분리하는 이유는?

남겨두면 `/put_old`를 통해 호스트의 이전 파일시스템에 접근할 경로가 남는다. 루트를 교체한 뒤 `cd /`와 이전 마운트 분리를 함께 처리해야 한다. 다만 이것만으로 권한 제한까지 끝나는 것은 아니다.

### Q2. namespace만 있고 cgroup이 없다면?

프로세스 목록이나 마운트 구성은 나뉘어도 별도의 사용량 상한은 없다. 부하가 큰 프로세스가 호스트의 자원을 소모해 다른 작업에 영향을 줄 수 있다.

### Q3. runtime의 부모와 자식은 무엇을 맡아야 할까?

부모는 rootfs와 cgroup을 준비하고, 자식 종료를 기다린 뒤 자원을 정리한다. 자식은 대상 프로그램을 실행하기 전에 cgroup에 들어가고 namespace, 루트, procfs를 구성한 뒤 `exec`한다. 호스트 기준 PID를 써야 하는 등록 작업은 PID namespace에 들어가기 전에 처리하면 혼동을 줄일 수 있다.

### Q4. pivot_root를 적용한 스크립트는?

2번에 정리했다. 이 스크립트는 루트와 namespace 구성까지 담당한다. cgroup 실험은 별도로 진행하며, 자동 등록과 정리는 6주차 통합 스크립트에 연결한다.

## 5. 정리

`pivot_root`로 루트 마운트를 바꾸고, cgroup으로 사용량을 제한한다. 격리와 제한은 별개이며 실행 순서도 중요하다. 프로그램을 시작한 뒤 제한을 거는 것보다 실행 전에 그룹에 넣는 방식이 맞다.

참고: [pivot_root(2)](https://man7.org/linux/man-pages/man2/pivot_root.2.html), [cgroup v2](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)
