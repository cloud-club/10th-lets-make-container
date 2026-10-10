# 3주차 - namespace와 mount

## 1. namespace

`chroot`는 `/`의 기준을 바꿨지만 hostname과 프로세스 목록까지 나누지는 않았다. 이런 자원의 이름과 보이는 범위를 나누는 기능이 namespace다.

| 종류 | 분리하는 대상 |
| --- | --- |
| UTS | hostname, domainname |
| PID | 프로세스 번호와 PID로 식별할 수 있는 범위 |
| mount | 파일시스템 마운트 구성 |
| network | 인터페이스, 라우팅 테이블, 포트 등 |
| IPC | System V IPC, POSIX 메시지 큐 등 |
| user | 사용자·그룹 ID와 권한의 범위 |
| cgroup | 보이는 cgroup 경로의 기준 |
| time | 단조 시계와 부팅 후 경과 시간 시계의 기준 |

```bash
echo $$
ls -l /proc/$$/ns
bash --norc
echo $$
ls -l /proc/$$/ns
exit
```

부모 셸과 자식 셸의 PID는 달라도 namespace 식별값은 같을 수 있다. 새 프로세스를 실행하면 기본적으로 부모의 namespace를 물려받는다.

## 2. UTS와 PID 분리

### hostname 변경

호스트에서 기존 이름을 확인하고 새 UTS namespace로 들어간다.

```bash
hostname
sudo unshare --uts bash
```

새 셸 안에서 이름을 바꾸고 나온다.

```bash
hostname week3
hostname
exit
```

호스트에서 다시 `hostname`을 실행해 비교한다. UTS만 분리했으므로 새 셸에서도 PID와 파일시스템은 기존 환경을 공유한다.

### PID와 ps의 기준

호스트에서 다음 두 구성을 각각 실행해 비교한다.

```bash
sudo unshare --pid --fork bash
# 새 셸 안에서
echo $$
ps -e -o pid,ppid,comm
exit
```

```bash
sudo unshare --pid --fork --mount-proc bash
# 새 셸 안에서
echo $$
ps -e -o pid,ppid,comm
exit
```

둘 다 셸의 PID는 1이다. 차이는 `ps`가 읽는 `/proc`이다. 첫 번째는 호스트의 procfs를 그대로 읽고, 두 번째는 새 PID namespace에 맞게 procfs를 다시 마운트한다.

`--fork`는 새 PID namespace에 들어갈 자식을 생성한다. `--mount-proc`는 mount namespace 생성도 포함한다.

## 3. rootfs와 결합하기

2주차의 `tmproot`를 사용한다. 이전 실습의 procfs는 해제된 상태여야 한다. 다음을 `makecontainer.sh`로 저장한다.

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
    mount --make-rprivate /
    hostname week3
    mkdir -p "$rootfs/proc"
    mount -t proc proc "$rootfs/proc"
    exec chroot "$rootfs" "$@"
' makecontainer-init "$rootfs" "$@"
```

호스트에서 실행한다.

```bash
chmod +x makecontainer.sh
sudo ./makecontainer.sh tmproot /bin/sh
```

내부에서는 `hostname`, `echo $$`, `ps`, `ls /`를 확인한다. hostname은 UTS, PID와 프로세스 목록은 PID namespace와 procfs, 파일 목록은 rootfs 설정의 결과다.

`mount --make-rprivate /`는 마운트 변경이 다른 namespace로 전파되지 않게 한다. mount namespace는 파일 자체를 복사하는 기능은 아니므로 `tmproot`의 파일을 수정하면 호스트에서도 바뀐 파일이 보인다.

`exit` 후 호스트에서 `findmnt --mountpoint tmproot/proc`로 마운트가 남았는지 확인한다. namespace를 유지하는 프로세스나 참조가 없다면 그 안에서 만든 마운트도 해제된다.

## 4. 심화 질문

### Q1. 같은 프로세스가 내부에서는 PID 1, 호스트에서는 다른 PID인 이유는?

PID는 namespace별로 부여되기 때문이다. 프로세스 하나가 자신이 속한 namespace와 그 상위 namespace에서 서로 다른 번호를 가진다.

### Q2. procfs를 다시 마운트하지 않으면 ps가 기대와 다른 이유는?

procfs는 마운트할 때의 PID namespace를 기준으로 정보를 보여준다. PID namespace만 바꾸고 기존 `/proc`을 읽으면 호스트 기준 목록이 계속 나온다. 기존 `/proc`을 bind mount해도 이 기준은 바뀌지 않는다.

### Q3. 현재 환경에 있는 것과 빠진 것은?

별도의 hostname, PID 공간, 마운트 구성과 rootfs가 있다. CPU·메모리 사용량은 제한하지 않았고 네트워크도 호스트와 공유한다. root 권한 자체를 줄이지도 않았다.

### Q4. rootfs와 실행 명령을 인자로 받는 스크립트는?

3번의 스크립트처럼 첫 인자를 rootfs로 받고 나머지는 `"$@"`로 전달한다. 문자열 하나로 합치지 않아 공백이 포함된 인자도 보존된다. 마지막 `exec`는 준비하던 셸을 대상 명령으로 교체하므로 PID 1이 유지된다.

## 5. 정리

namespace는 종류별로 조합해야 한다. PID namespace를 만들었다고 파일 경로나 네트워크까지 분리되는 것은 아니다. 특히 프로세스 번호를 나누는 것과 그 목록을 읽는 procfs를 준비하는 것을 구분해야 한다.
