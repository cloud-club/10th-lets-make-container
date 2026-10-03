## 1. pivot_root 후 이전 루트를 put_old에서 분리하는 이유는 무엇일까?
- 답: `pivot_root`를 하면 기존 root가 `/put_old`로 이동한다.  
따라서 `/put_old`를 `umount`하여 기존 root를 제거하고 새로운 rootfs(새롭게 사용할 컨테이너의 /)만 사용하기 위해서이다.
<img width="721" height="788" alt="image" src="https://github.com/user-attachments/assets/e82bcf5b-cb1c-4e49-86f6-11389fd3a9c7" />
-> chroot만 사용하면 강의에서 설명한대로 탈옥이 되었는데 이문제를 pivot root를 사용하면 해결이 된다! 정말로 root디렉토리가 바뀐거다
<img width="1450" height="666" alt="image" src="https://github.com/user-attachments/assets/409adba4-4a7b-4bd0-a933-caec3c34ea3c" />

## 2. namespace와 cgroup은 각각 어떤 문제를 해결할까? namespace만 만들고 cgroup을 만들지 않으면 부하가 큰 프로세스에서 무엇이 달라질까?
- 답: namespace는 **무엇을 볼 수 있는지 격리**하고, cgroup은 **CPU나 메모리를 얼마나 사용할 수 있는지 제한**한다.프로세스나 hostname 같은 환경은 격리할 수 있다. 하지만 CPU나 메모리를 많이 사용하는 프로세스가 실행되면 호스트의 자원을 많이 사용할 수 있다.

## 3. rootfs·namespace·cgroup을 사람이 순서대로 설정하는 대신 runtime이 처리하려면 부모와 자식 프로세스가 각각 어떤 일을 맡아야 할까?
- 답: 부모는 컨테이너 실행을 위한 준비와 관리를 하고, 자식은 namespace와 rootfs를 설정한 뒤 실제 프로그램을 실행한다.

## 4. 3주차의 스크립트에서 pivot_root와 이전 루트 정리까지 수행하도록 추가하여 제출해주세요. rootfs와 실행할 명령을 인자로 받으면 됩니다. 예: sudo ./makecontainer.sh /home/ubuntu/tmproot /bin/sh
- Week 3에서는 `unshare`와 `chroot`를 이용하여 rootfs와 PID, UTS, mount 환경을 분리하였다.
- Week 4에서는 chroot 대신 pivot_root를 사용하여 rootfs를 새로운 /로 변경하고, 기존 root를 /put_old로 이동한 뒤 /put_old에 연결된 기존 root의 mount를 umount하여 분리한다

## 3. Week 3 `makecontainer.sh` 수정

```sh
#!/bin/sh

set -e

# rootfs 경로를 첫 번째 인자로 받음
ROOTFS="$1"

# rootfs가 없으면 종료
if [ -z "$ROOTFS" ] || [ ! -d "$ROOTFS" ]; then
    echo "usage: $0 <rootfs-dir> [command...]" >&2
    exit 1
fi

# rootfs 인자를 제거하고 실행할 명령만 남김
shift

# 명령어가 없으면 /bin/sh 실행
[ $# -eq 0 ] && set -- /bin/sh

# UTS, PID, Mount namespace 생성
# --fork를 사용하여 새로운 PID namespace에서 프로세스 실행
exec unshare --uts --pid --fork --mount sh -c '

    # rootfs 경로 저장
    ROOTFS="$1"
    shift

    # mount 변경사항이 다른 namespace로 전파되지 않도록 설정
    mount --make-rprivate /

    # hostname 설정
    hostname "$(basename "$ROOTFS")"

    # rootfs를 bind mount
    # pivot_root에서 새로운 root로 사용하기 위한 과정
    mount --bind "$ROOTFS" "$ROOTFS"

    # 기존 root가 이동할 디렉터리 생성
    mkdir -p "$ROOTFS/put_old"

    # rootfs로 이동
    cd "$ROOTFS"

    # rootfs를 새로운 /로 변경
    # 기존 root는 /put_old로 이동
    pivot_root . put_old

    # 새로운 root로 이동
    cd /

    # PID namespace에 맞는 procfs mount
    mount -t proc proc /proc

    # /put_old에 연결된 기존 root의 mount를 분리
    umount -l /put_old

    # 빈 /put_old 디렉터리 삭제
    rmdir /put_old

    # 실제 컨테이너 명령 실행
    exec "$@"

' sh "$ROOTFS" "$@"
```

- 실행방법
```sh
chmod +x makecontainer.sh

sudo ./makecontainer.sh /home/ubuntu/tmproot /bin/sh
```

- 컨테이너 내부에서 확인한다.

```sh
hostname
echo $$
ls /
ps
```

- `ps`를 통해 PID namespace 안의 프로세스를 확인할 수 있다.


## 5. 정리
 
Week 3에서는 namespace와 `chroot`를 이용하여 컨테이너의 실행 환경을 격리하였다.
Week 4에서는 `pivot_root`를 이용하여 rootfs를 새로운 `/`로 변경하고, 기존 root를 `/put_old`로 이동한 후 `umount`하였다.
또한 cgroup을 이용하여 CPU와 메모리 사용량을 제한하였다.

정리하면 다음과 같다.

| 기능 | 역할 |
|---|---|
| namespace | 실행 환경 격리 |
| `pivot_root` | 컨테이너의 rootfs를 새로운 `/`로 변경 |
| cgroup | CPU와 메모리 자원 제한 |

### 한 문장 정리

namespace로 환경을 격리하고, `pivot_root`로 rootfs를 교체하고, cgroup으로 자원 사용량을 제한한다.
