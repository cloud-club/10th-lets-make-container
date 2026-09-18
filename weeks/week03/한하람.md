### 1. 같은 프로세스가 컨테이너 안에서는 PID 1, 호스트에서는 다른 PID로 보일 수 있는 이유는 무엇일까?

namespace 계층 구조에 따라 동일한 프로세스에 대해 독립적인 PID 매핑을 유지한다.

- 프로세스는 생성될 때 자신이 속한 PID namespace 안에서 번호를 부여받습니다.
- 새로 생성한 PID namespace에서 첫 번째 프로세스는 PID 1을 갖지만, 호스트 namespace에서는 전체 시스템을 기준으로 PID 번호를 매핑한다.

### 2. 새 PID namespace에서 procfs를 다시 mount하지 않으면 `ps` 결과는 왜 기대와 달라질까?

`ps` 명령어는 현재 실행 중인 프로세스 정보를 **/proc** 가상 파일 시스템에서 읽어오는데, 새로 마운트하지 않으면 격리 이전(호스트)의 **/proc**을 참조합니다.

- PID namespace를 분리하더라도, 마운트된 **/proc** 가 갱신되지 않으면 `ps` 명령어는 호스트의 프로세스 목록을 출력하게 됩니다.

### 3. namespace와 전용 rootfs를 결합한 현재 환경에는 컨테이너의 어떤 성질이 있고, 무엇이 아직 제한되거나 연결되지 않았을까?

파일 시스템과 PID가 격리되어있다. 하드웨어 자원 제한, 네트워크 통신 기능, 권한 등은 아직 격리되지 않았습니다.

- rootfs(chroot), mount namespace를 통한 파일 시스템 격리
- PID namespace를 통한 프로세스 격리
- UTS namespace를 통한 호스트명 격리

### 4. 4번 실습의 명령을 `makecontainer.sh`로 만들고, chmod +x 권한을 준 다음 실행해보세요. rootfs 경로와 실행할 명령을 인자로 받을 수 있도록 개선해봅시다.

```bash
cat makecontainer.sh

#!/bin/bash

ROOTFS=$1
shift
CMD="$@"

sudo unshare --uts --pid --fork --mount bash -c "
	mount --make-rprivate /
	hostname week3
	
	mkdir -p $ROOTFS/proc
	mount -t proc proc $ROOTFS/proc
	findmnt --mountpoint $ROOTFS/proc
	exec chroot $ROOTFS $CMD
"
```

`#!/bin/bash` : 스크립트를 bash 셸 환경에서 실행하겠다고 선언 (쉬뱅)

`ROOTFS=$1` : 스크립트를 실행할 때 첫 번째 인자를 ROOTFS라는 변수에 저장

`shift`: 입력받은 인자를 왼쪽으로 한 칸씩 밀어냄(2 → 1), 

`CMD="$@”`: 남은 모든 인자를 CMD 변수에 저장

`-c` (command): “ “ 안에 실행할 명령어라는 것을 알려줌

```bash
./makecontainer.sh tmproot /bin/sh
TARGET                    SOURCE FSTYPE OPTIONS
/home/ubuntu/tmproot/proc proc   proc   rw,relatime
/ # ls
-      bin    dev    etc    home   lib    lib64  p      proc   root   sys    tmp    usr    var
/ # 
```