#!/usr/bin/env bash
#
# makecontainer.sh - 이미지 이름을 받아 컨테이너를 실행한다
#
#   단계마다 집이 한 층씩 지어진다. 그림이 거슬리면 --quiet.
#
# usage:
#   sudo ./makecontainer.sh busybox:latest -- /bin/sh
#   sudo ./makecontainer.sh --workdir /tmp/run1 --quiet alpine:3.20 -- /bin/sh
#
set -euo pipefail

IMAGE=""
MEM_MAX=52428800
CPU_MAX=""
NEW_HOSTNAME="kuma-house"
BASE_DIR="$PWD"
KEEP=0
QUIET=0

CID=""
CG_PATH=""
CREATED=0

usage() {
  cat >&2 <<'EOF'
usage: makecontainer.sh [options] <image> [--] <command> [args...]

options:
  --memory <bytes|none>  메모리 상한 (기본: 52428800 = 50MiB)
  --cpu "<quota> <period>"
                         CPU 상한 (예: "50000 100000")
  --hostname <name>      컨테이너 hostname (기본: kuma-house)
  --workdir <dir>        작업 디렉터리 (기본: 현재 디렉터리)
  --keep                 종료 후 tmproot/upper/work/merged 유지
  --quiet                그림 없이 실행

example:
  sudo ./makecontainer.sh busybox:latest -- /bin/sh
EOF
  exit 1
}

# ------------------------------------------------------------- 인자 파싱
while [ $# -gt 0 ]; do
  case "$1" in
    --memory)   MEM_MAX="${2:-}";      shift 2 ;;
    --cpu)      CPU_MAX="${2:-}";      shift 2 ;;
    --hostname) NEW_HOSTNAME="${2:-}"; shift 2 ;;
    --workdir)  BASE_DIR="${2:-}";     shift 2 ;;
    --keep)     KEEP=1;                shift   ;;
    --quiet)    QUIET=1;               shift   ;;
    -h|--help)  usage ;;
    --)         shift; break ;;
    -*)         echo "알 수 없는 옵션: $1" >&2; usage ;;
    *)
      if [ -z "$IMAGE" ]; then IMAGE="$1"; shift
      else break
      fi
      ;;
  esac
done

CMD=("$@")
[ -n "$IMAGE" ] || usage
[ ${#CMD[@]} -gt 0 ] || CMD=(/bin/sh)
[ "$(id -u)" -eq 0 ] || { echo "root 권한이 필요합니다. sudo로 실행하세요." >&2; exit 1; }
command -v docker >/dev/null || { echo "docker가 필요합니다(이미지에서 파일을 꺼낼 때만 사용)." >&2; exit 1; }

# ------------------------------------------------------------- 그림
# 상자 안은 ASCII만 쓴다. 한글은 터미널에서 두 칸을 먹어 테두리가 어긋난다.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_DIM=$'\033[2m'; C_AMBER=$'\033[33m'; C_GREEN=$'\033[32m'
  C_PINK=$'\033[35m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
  C_DIM=""; C_AMBER=""; C_GREEN=""; C_PINK=""; C_BOLD=""; C_OFF=""
fi

step() {
  [ "$QUIET" -eq 1 ] && return 0
  printf '\n%s[%s/8]%s %s%s%s %s%s%s\n' \
    "$C_DIM" "$1" "$C_OFF" "$C_BOLD" "$2" "$C_OFF" "$C_DIM" "${3:-}" "$C_OFF"
}

art() {
  [ "$QUIET" -eq 1 ] && return 0
  printf '%s%s%s\n' "$C_AMBER" "$1" "$C_OFF"
}

# ------------------------------------------------------------- 경로 준비
mkdir -p "$BASE_DIR"
BASE_DIR=$(readlink -f "$BASE_DIR")
LOWER="$BASE_DIR/tmproot"
UPPER="$BASE_DIR/upper"
WORK="$BASE_DIR/work"
MERGED="$BASE_DIR/merged"

for d in "$LOWER" "$UPPER" "$WORK" "$MERGED"; do
  if [ -e "$d" ]; then
    echo "이미 존재합니다: $d" >&2
    echo "--workdir 로 다른 디렉터리를 지정하거나 기존 자원을 먼저 정리하세요." >&2
    exit 1
  fi
done

if [ "$QUIET" -eq 0 ]; then
  printf '\n%s   ʕ •ᴥ• ʔ   집 지으러 왔습니다%s\n' "$C_PINK" "$C_OFF"
  art '   ~~~~~~~~~~~~~~~~~   '
fi

# ------------------------------------------------------------- 정리
cleanup() {
  if [ -n "$CID" ]; then
    docker rm -v "$CID" >/dev/null 2>&1 || true
  fi

  if [ -n "$CG_PATH" ] && [ -d "$CG_PATH" ]; then
    rmdir "$CG_PATH" 2>/dev/null \
      || echo "cgroup 정리 실패(프로세스 잔류 가능): $CG_PATH" >&2
  fi

  if [ "$CREATED" -eq 1 ] && [ "$KEEP" -eq 0 ]; then
    mountpoint -q "$MERGED" && umount "$MERGED" 2>/dev/null || true
    rm -rf "$LOWER" "$UPPER" "$WORK"
    rmdir "$MERGED" 2>/dev/null || true
    if [ "$QUIET" -eq 0 ]; then
      printf '\n%s   ʕ •ᴥ• ʔ   집 철거 완료. 터만 남았습니다%s\n\n' "$C_PINK" "$C_OFF"
    fi
  elif [ "$KEEP" -eq 1 ]; then
    [ "$QUIET" -eq 1 ] || printf '\n%s   집을 남겨둡니다: %s%s\n\n' "$C_DIM" "$BASE_DIR" "$C_OFF"
  fi
}
trap cleanup EXIT

# ------------------------------------------------------------- 1. 가구 반입
step 1 "가구 트럭 도착" "2주차 · rootfs 꺼내기"
art '   +----------------+'
art '   |  bed desk pot  |'
art "   +----------------+   $IMAGE"

mkdir -p "$LOWER" "$UPPER" "$WORK" "$MERGED"
CREATED=1

CID=$(docker create "$IMAGE")
docker export "$CID" | tar -C "$LOWER" -xf -
docker rm -v "$CID" >/dev/null
CID=""

[ -x "$LOWER/bin/sh" ] || echo "경고: $LOWER/bin/sh 를 찾지 못했습니다." >&2

# ------------------------------------------------------------- 2. 덮개 준비
step 2 "투명 덮개 재단" "6주차 · upper / work / merged"
art '   ................   <- upper (아직 비어 있음)'
art '   ################   <- lower (원본, 못 고침)'

# ------------------------------------------------------------- 3. 계량기
if [ "$MEM_MAX" != "none" ] || [ -n "$CPU_MAX" ]; then
  if [ "$(stat -fc %T /sys/fs/cgroup)" != "cgroup2fs" ]; then
    echo "cgroup v2가 아닙니다. 자원 제한 없이 진행합니다." >&2
  else
    step 3 "계량기 설치" "4주차 · cgroup v2"
    CG_PATH="/sys/fs/cgroup/kuma-$$"
    mkdir -p "$CG_PATH"

    if [ "$MEM_MAX" != "none" ]; then
      echo "$MEM_MAX" > "$CG_PATH/memory.max"
      echo 0          > "$CG_PATH/memory.swap.max"
      art "   +-- honey --+"
      art "   | ##....... |   memory.max = $MEM_MAX"
      art "   +-----------+"
    fi
    if [ -n "$CPU_MAX" ]; then
      echo "$CPU_MAX" > "$CG_PATH/cpu.max"
      art "   +-- power --+"
      art "   | ####..... |   cpu.max = $CPU_MAX"
      art "   +-----------+"
    fi
  fi
else
  step 3 "계량기 생략" "4주차 · --memory none"
fi

# ------------------------------------------------------------- 4~8. 자식
export LOWER UPPER WORK MERGED NEW_HOSTNAME QUIET
export C_DIM C_AMBER C_PINK C_BOLD C_OFF

CHILD_SETUP='
  set -eu

  step() {
    [ "$QUIET" -eq 1 ] && return 0
    printf "\n%s[%s/8]%s %s%s%s %s%s%s\n" \
      "$C_DIM" "$1" "$C_OFF" "$C_BOLD" "$2" "$C_OFF" "$C_DIM" "${3:-}" "$C_OFF"
  }
  art() {
    [ "$QUIET" -eq 1 ] && return 0
    printf "%s%s%s\n" "$C_AMBER" "$1" "$C_OFF"
  }

  mount --make-rprivate /
  hostname "$NEW_HOSTNAME"

  step 4 "벽 세우기" "3주차 · mount uts pid ipc"
  art "   ##############"
  art "   #            #"
  art "   #            #"
  art "   ##############"

  mount -t overlay overlay \
    -o lowerdir="$LOWER",upperdir="$UPPER",workdir="$WORK" \
    "$MERGED"

  step 5 "덮개 씌우기" "6주차 · OverlayFS"
  art "   ##############"
  art "   # .......... #"
  art "   # ########## #"
  art "   ##############"

  cd "$MERGED"
  mkdir -p put_old
  pivot_root . put_old
  cd /

  export PATH=/bin:/sbin:/usr/bin:/usr/sbin
  hash -r

  umount -l /put_old
  rmdir /put_old

  step 6 "이사 완료" "4주차 · pivot_root + put_old 분리"
  art "   ##############"
  art "   #  bed desk  #"
  art "   #            #"
  art "   #####  #######   <- 바깥문 잠금"

  mkdir -p /proc
  mount -t proc proc /proc

  step 7 "가족 명부 비치" "1주차 · procfs"
  art "   ##############"
  art "   #  1 2 3 ... #"
  art "   #  bed desk  #"
  art "   ##############"

  step 8 "입주" "1주차 · exec, 여기서 PID 1"
  art "   ##############"
  art "   #   ( . . )  #"
  art "   #    (ᴥ)     #"
  art "   ##############"
  if [ "$QUIET" -eq 0 ]; then
    printf "\n%s   곰이 들어갔습니다. hostname=%s, pid=%s%s\n" "$C_PINK" "$(hostname)" "$$" "$C_OFF"
    printf "\n%s   오늘 쓴 것들%s\n" "$C_BOLD" "$C_OFF"
    printf "%s" "$C_DIM"
    printf "   1주차  프로세스, PID 1, procfs      -> [7] [8]\n"
    printf "   2주차  이미지에서 rootfs 꺼내기     -> [1]\n"
    printf "   3주차  namespace 로 벽 세우기       -> [4]\n"
    printf "   4주차  pivot_root, cgroup           -> [3] [6]\n"
    printf "   5주차  veth, bridge, NAT            -> 이번 실행에서는 생략\n"
    printf "   6주차  OverlayFS, capability        -> [2] [5], capability 는 미적용\n"
    printf "%s\n" "$C_OFF"
  fi

  exec "$@"
'

NS_CMD=(
  unshare --mount --uts --pid --ipc --fork --propagation private --
  /bin/bash -c "$CHILD_SETUP" makecontainer-init "${CMD[@]}"
)

set +e
if [ -n "$CG_PATH" ]; then
  bash -c 'echo $$ > "$1/cgroup.procs"; shift; exec "$@"' \
    bash "$CG_PATH" "${NS_CMD[@]}"
else
  "${NS_CMD[@]}"
fi
STATUS=$?
set -e

exit "$STATUS"
