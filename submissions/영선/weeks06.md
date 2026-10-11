### image 명을 받아 컨테이너를 실행할 수 있도록 스크립트를 만들어서 제출해주세요! (네트워크 같은 것들은 너무 복잡해질 수 있어 제외해도 좋습니다)

```

#!/usr/bin/env bash
set -euo pipefail

IMAGE="$1"
shift 2
CMD=("$@")

mkdir tmproot upper work merged

cid=$(docker create --pull=never "$IMAGE")
docker export "$cid" | tar -C tmproot -xf -
docker rm -v "$cid"

rootfs=$(realpath merged)

mount -t overlay overlay \
  -o lowerdir="$(realpath tmproot)",upperdir="$(realpath upper)",workdir="$(realpath work)" \
  merged

rootfs=$(realpath merged)

exec unshare --uts --pid --fork --mount bash -c '
    set -euo pipefail
    rootfs=$1
    shift

    mount --make-rprivate /
    hostname myhost

    mkdir -p "$rootfs/put_old"
    cd "$rootfs"
    pivot_root . put_old
    cd /
    hash -r

    umount -l /put_old
    rmdir /put_old
    mkdir -p /proc
    mount -t proc proc /proc

    exec "$@"
' makecontainer-init "$rootfs" "${CMD[@]}"

```

### 그림의 file2가 lowerdir와 upperdir에 모두 있을 때 어느 파일을 읽을까요? 이 실습에서 원본 tmproot를 직접 /로 사용하면 무엇이 달라질까요?
upperdir의 file2를 읽습니다. upperdir가 변경된 파일이라 우선시하기 때문입니다.


### 셸을 종료하는 것, OverlayFS를 unmount하는 것, upper를 삭제하는 것은 파일 변경분에 각각 어떤 영향을 줄까요?
셸 종료	- 변경분 유지, 셸만 종료됨
OverlayFS unmount	- 변경분 유지, OverlayFS만 마운트 해제됨
upper 삭제	- 변경분 삭제됨

같은 upper를 다시 연결하면 이전 변경분이 유지됩니다. upper를 삭제하고 새로 만들면 원본 기준으로 시작합니다.

### namespace와 OverlayFS를 적용한 스크립트는 프로세스의 자원 사용량과 특권도 제한할까요? 각각 어떤 기능이 더 필요할까요?

수업자료에 있는 CAP_SYS_ADMIN cgroups 는 하지 않았다. 그러므로 관리자 권한제어, 자원 사용량제한은 하지 않는다.
격리랑 권리제한이 별도로 필요하다.
