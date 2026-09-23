1.같은 프로세스가 컨테이너 안에서는 PID 1, 호스트에서는 다른 PID로 보일 수 있는 이유는 무엇일까?
PID namespace마다 같은 프로세스에 다른 PID를 부여할 수 있기 때문 컨테이너로 독립된 환경의 핵심 아닐까 생각

2.새 PID namespace에서 procfs를 다시 mount하지 않으면 ps 결과는 왜 기대와 달라질까?
새 PID namespace를 만들어도 기존 /proc을 그대로 보면 ps는 호스트 기준 정보를 읽는다. 따라서 mount namespace를 분리하고(--mount), 그 안에서 새 PID namespace 기준으로 procfs를 다시 마운트해야 한다.

3.namespace와 전용 rootfs를 결합한 현재 환경에는 컨테이너의 어떤 성질이 있고, 무엇이 아직 제한되거나 연결되지 않았을까?
컨테이너 처럼 격리된 환경(pid, 내부 실행 process )까지는 확실한 데 네트워크같은 거나 아직 분리 X cpu 나 그런 것도 분리되어야 하는 걸로 알음

4. 는 그냥 bash 로 여태 한 명령어 묶음 되는 듯.
```bash
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
    mount --make-rprivate /
    hostname week3

    mkdir -p $ROOTFS/proc
    mount -t proc proc $ROOTFS/proc

    exec chroot $ROOTFS $CMD
  "

```