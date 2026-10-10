#!/usr/bin/env bash
set -euo pipefail

# BusyBox 계열 이미지를 사용하는 실습용 실행기.
if (( $# < 3 )) || [[ $2 != -- ]]; then
    echo "사용법: sudo $0 IMAGE -- COMMAND [ARG...]" >&2
    exit 2
fi
if (( EUID != 0 )); then
    echo "root 권한으로 실행해야 합니다." >&2
    exit 1
fi
image=$1
shift 2
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
for tool in docker unshare mount pivot_root bash tar; do
    command -v "$tool" >/dev/null || { echo "필요한 명령: $tool" >&2; exit 1; }
done
[[ $(stat -fc %T /sys/fs/cgroup) == cgroup2fs ]] || {
    echo "cgroup v2 환경이 필요합니다." >&2
    exit 1
}

# 기존 실습 파일은 건드리지 않고 별도 디렉터리에서 실행한다.
run_dir=/var/tmp/makecontainer-study
cg=/sys/fs/cgroup/makecontainer-study-$$
cid=
cg_created=0
mkdir -m 700 "$run_dir" || {
    echo "$run_dir 가 이미 있거나 생성할 수 없습니다. 기존 상태를 확인하세요." >&2
    exit 1
}

cleanup() {
    local status=$?
    trap - EXIT
    set +e
    if [[ -n $cid ]]; then
        docker rm -v "$cid" >/dev/null || status=1
    fi
    if (( cg_created )); then
        # PID 1 종료 후 남아 있는 준비 프로세스까지 정리한다.
        if grep -q '^populated 1$' "$cg/cgroup.events"; then
            echo 1 > "$cg/cgroup.kill"
            for ((i=0; i<50; i++)); do
                grep -q '^populated 1$' "$cg/cgroup.events" || break
                sleep 0.1
            done
        fi
        if grep -q '^populated 1$' "$cg/cgroup.events"; then
            echo "프로세스가 남아 있어 $run_dir 와 $cg 를 보존합니다." >&2
            exit 1
        fi
        rmdir "$cg" || status=1
    fi
    # OverlayFS는 자식의 mount namespace에만 존재한다.
    rm -rf --one-file-system -- "$run_dir" || status=1
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir "$run_dir"/{lower,upper,work,merged}
docker image inspect "$image" >/dev/null 2>&1 || docker pull "$image"
# 이미지의 CMD/ENTRYPOINT는 적용하지 않고 파일만 꺼낸다.
cid=$(docker create --entrypoint /bin/sh "$image")
docker export "$cid" | tar -C "$run_dir/lower" -xf -
docker rm -v "$cid" >/dev/null
cid=
[[ -x $run_dir/lower/bin/busybox ]] || {
    echo "이 실습 스크립트는 /bin/busybox가 있는 이미지를 사용합니다." >&2
    exit 1
}

mkdir "$cg"
cg_created=1
for setting in memory.max memory.swap.max cgroup.kill; do
    [[ -f $cg/$setting ]] || {
        echo "필요한 cgroup 파일이 없습니다: $cg/$setting" >&2
        exit 1
    }
done
echo 52428800 > "$cg/memory.max"
echo 0 > "$cg/memory.swap.max"

# 별도 Bash가 호스트 PID로 cgroup에 먼저 들어간다. 부모는 밖에 남는다.
bash -c '
    set -euo pipefail
    cg=$1
    shift
    echo $$ > "$cg/cgroup.procs"
    exec unshare --uts --pid --fork --kill-child=KILL --mount --net --ipc \
        bash -c '\''
        set -euo pipefail
        run_dir=$1
        shift
        mount --make-rprivate /
        hostname makecontainer
        mount -t overlay overlay \
            -o "lowerdir=$run_dir/lower,upperdir=$run_dir/upper,workdir=$run_dir/work" \
            "$run_dir/merged"
        mkdir "$run_dir/merged/put_old"
        cd "$run_dir/merged"
        pivot_root . put_old
        cd /
        hash -r
        /bin/busybox umount -l /put_old
        /bin/busybox rmdir /put_old
        /bin/busybox mkdir -p /proc
        /bin/busybox mount -t proc proc /proc
        exec "$@"
    '\'' makecontainer-init "$@"
' makecontainer-host "$cg" "$run_dir" "$@"
