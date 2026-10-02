### 같은 프로세스가 컨테이너 안에서는 PID 1, 호스트에서는 다른 PID로 보일 수 있는 이유는 무엇일까?

- pid namespace를 통해 프로세스에게 서로다른 pid 번호를 보여줄수있다.
  (새 공간에서 새로운 이름 지정하면, 같은 프로세스더라도 다른pid로 보이는것)
  => pid는 절대적인 고유번호가 아님!


### 새 PID namespace에서 procfs를 다시 mount하지 않으면 ps 결과는 왜 기대와 달라질까?

- `/proc` : 프로세스 정보확인하는것, 커널이 제공하는 파일시스템(procfs)
새로운 네임스페이스가 생겨도 기존의 /proc내용까지 자동으로 바뀌진 않음
기존 정보를 그대로 바라볼수있음
그래서 ps도 원래 호스트쪽 프로세스가 보일수 있는것.
=> 따라서 mount를 통해 /proc도 마운트 해줘야함 `mount -t proc proc /proc`

(PID namespace는 "프로세스를 보는 범위"를 바꾸고, procfs는 ps가 그 범위를 확인할 수 있게 해주는 창문이다.)

### namespace와 전용 rootfs를 결합한 현재 환경에는 컨테이너의 어떤 성질이 있고, 무엇이 아직 제한되거나 연결되지 않았을까?
- rootfs까지 결합시 파일시스템이 격리된다.(chroot)
- namespace -> 프로세스, 호스트네임 처럼 프로세스를 바라보는 범위가 분리된다.
  컨테이너 기본 조건인 전용 파일시스템, 프로세스, 호스트네임, 마운트 환경이 갖추어짐.

  그러나 아직 도커와의 차이점은?
  - 네트워크가 같음
  - 권한, 보안설정 등을 분리하지 않음.
 
    
4번 실습의 명령을 makecontainer.sh로 만들고, chmod +x 권한을 준 다음 실행해보세요. rootfs 경로와 실행할 명령을 인자로 받을 수 있도록 개선해봅시다.
chmod +x makecontainer.sh 
./makecontainer.sh tmproot /bin/sh


```bash
#!/bin/bash

ROOTFS=$1
COMMAND=$2

if [ -z "$ROOTFS" ] || [ -z "$COMMAND" ]; then
    echo "사용법: $0 <rootfs> <command>"
    exit 1
fi

sudo unshare --uts --pid --fork --mount bash -c "
    mount --make-rprivate /
    hostname week3

    mkdir -p $ROOTFS/proc
    mount -t proc proc $ROOTFS/proc

    exec chroot $ROOTFS $COMMAND
"
```
