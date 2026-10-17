#!/usr/bin/env bash
#
# compare.sh - docker 컨테이너와 makecontainer.sh 컨테이너를 같은 항목으로 비교한다
#
# usage:
#   sudo ./compare.sh
#   sudo ./compare.sh --image alpine:3.20
#
set -uo pipefail

IMAGE="busybox:latest"
MEM="52428800"
WORKDIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --image)   IMAGE="${2:-}";   shift 2 ;;
    --memory)  MEM="${2:-}";     shift 2 ;;
    --workdir) WORKDIR="${2:-}"; shift 2 ;;
    -h|--help)
      echo "usage: sudo ./compare.sh [--image busybox:latest] [--memory 52428800]" >&2
      exit 1 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
  esac
done

[ "$(id -u)" -eq 0 ] || { echo "root 권한이 필요합니다. sudo로 실행하세요." >&2; exit 1; }
command -v docker >/dev/null || { echo "docker가 필요합니다." >&2; exit 1; }
[ -x ./makecontainer.sh ] || { echo "./makecontainer.sh 가 없거나 실행 권한이 없습니다." >&2; exit 1; }

[ -n "$WORKDIR" ] || WORKDIR="/tmp/compare-$$"

# ------------------------------------------------------------- 검사 항목
# 양쪽 컨테이너 안에서 똑같이 실행할 스크립트.
# busybox sh 에서 돌아야 하므로 bash 전용 문법을 쓰지 않는다.
PROBE='
echo "내 PID            : $$"
echo "hostname          : $(hostname 2>/dev/null)"
echo "보이는 프로세스 수: $(ps 2>/dev/null | wc -l)"
echo "1번 프로세스      : $(cat /proc/1/comm 2>/dev/null || echo 확인불가)"
echo "네트워크 인터페이스: $(ls /sys/class/net 2>/dev/null | tr "\n" " " || echo 확인불가)"
echo "cgroup 경로       : $(cat /proc/self/cgroup 2>/dev/null | head -1 || echo 확인불가)"
echo "메모리 상한       : $(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo 확인불가)"
if mount -t tmpfs tmpfs /mnt 2>/dev/null; then
  echo "mount 시도        : 성공 (권한 남아 있음)"
  umount /mnt 2>/dev/null
else
  echo "mount 시도        : 실패 (권한 없음)"
fi
'

hr() { printf '%s\n' "------------------------------------------------------------------------"; }

echo
hr
echo " 컨테이너 비교 : docker  vs  makecontainer.sh"
echo " 이미지 $IMAGE / 메모리 상한 $MEM 바이트"
hr

# ------------------------------------------------------------- docker 쪽
echo
echo "[1] docker 컨테이너"
hr
DOCKER_OUT=$(docker run --rm --memory "$MEM" "$IMAGE" sh -c "$PROBE" 2>&1)
printf '%s\n' "$DOCKER_OUT"

# ------------------------------------------------------------- 우리 쪽
echo
echo "[2] makecontainer.sh 컨테이너"
hr
OURS_OUT=$(./makecontainer.sh --quiet --memory "$MEM" --workdir "$WORKDIR" \
             "$IMAGE" -- /bin/sh -c "$PROBE" 2>&1)
printf '%s\n' "$OURS_OUT"

# ------------------------------------------------------------- 나란히 보기
echo
echo "[3] 나란히 보기"
hr
if command -v column >/dev/null; then
  paste -d '|' \
    <(printf '%s\n' "$DOCKER_OUT") \
    <(printf '%s\n' "$OURS_OUT") \
  | column -t -s '|' 2>/dev/null || {
      echo "(column 실패, 위 [1][2] 를 참고하세요)"
    }
else
  echo "(column 명령이 없어 생략합니다. 위 [1][2] 를 참고하세요)"
fi

# ------------------------------------------------------------- 해설
echo
echo "[4] 읽는 법"
hr
cat <<'EOF'
같은 것 — 여기까지는 직접 만든 컨테이너도 도커와 동일하다

  내 PID            PID namespace 가 적용되어 양쪽 다 1번부터 시작한다
  hostname          UTS namespace 가 적용되어 호스트 이름과 다르다
  보이는 프로세스 수 자기 namespace 의 프로세스만 보인다
  cgroup 경로       각자 전용 cgroup 에 들어가 있다

다른 것 — 아직 하지 않은 부분이 여기서 드러난다

  네트워크 인터페이스
      docker  : 전용 eth0 를 갖는다
      ours    : network namespace 를 나누지 않아 호스트 것이 그대로 보인다
      5주차에서 veth, bridge, NAT 로 직접 구성해봤지만 이 스크립트에는 넣지 않았다

  메모리 상한
      docker  : 컨테이너 안에서 cgroup 파일을 읽을 수 있다
      ours    : /sys 를 마운트하지 않아 안에서는 확인할 수 없다
      제한 자체는 걸려 있다. 호스트에서 cgroup.procs 로 확인할 수 있다

  mount 시도
      docker  : 실패한다. 기본 허용 목록에서 CAP_SYS_ADMIN 을 빼기 때문이다
      ours    : 성공한다. namespace 를 나눠도 capability 는 그대로 남는다
      이것이 이 스크립트에 가장 크게 빠진 조각이다
EOF
echo
