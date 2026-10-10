# 1주차 - Linux 프로세스

## 1. Linux 프로세스

Linux에서는 프로세스 정보도 `/proc` 파일시스템을 통해 확인할 수 있다.

```bash
ls /proc
cat /proc/cpuinfo
cat /proc/meminfo
```

숫자로 된 디렉터리는 현재 보이는 프로세스의 PID에 해당한다. `cpuinfo`와 `meminfo`에서는 CPU 정보와 메모리 정보를 확인한다.

- 프로그램: 디스크에 저장된 실행 파일
- 프로세스: 실행 중인 프로그램
- PID: 프로세스를 식별하는 번호
- PPID: 부모 프로세스의 PID

프로세스는 부모-자식 관계를 가진다. 일반적으로 셸이 외부 명령을 실행할 때는 `fork()`로 자식을 만들고, 자식이 `exec()`로 실행할 프로그램을 교체한다. `fork()`는 새 PID를 만들지만 `exec()`는 PID를 유지한다.

`cd`처럼 셸 자체의 상태를 바꾸는 내장 명령은 보통 현재 셸에서 직접 처리한다.

## 2. 프로세스 실행 및 확인

### 부모-자식 프로세스

```bash
echo "shell pid: $$"
sleep 100 &
sleep_pid=$!
echo "sleep pid: $sleep_pid"
ps -o pid,ppid,comm -p "$$,$sleep_pid"
wait "$sleep_pid"
```

`$$`는 현재 셸의 PID, `$!`는 가장 최근에 실행한 백그라운드 프로세스의 PID다. `&`를 붙이면 셸이 명령 종료를 기다리지 않고 다음 명령을 받는다.

확인할 부분은 `sleep`의 PPID가 셸의 PID와 같은지다. 마지막 `wait`는 백그라운드 작업이 끝날 때까지 기다리고 종료 상태를 회수한다.

### 프로세스 트리

```bash
pstree -p
ps -ef
```

`pstree`는 부모-자식 관계를 트리로 보여준다. 일반적인 systemd 기반 VM에서는 PID 1인 `systemd` 아래로 서비스들이 이어진다. SSH로 접속한 셸도 `sshd`에서 이어지는 관계를 찾을 수 있다.

## 3. Docker 컨테이너의 프로세스

Linux VM의 터미널 A에서 BusyBox 컨테이너를 실행한다.

```bash
docker run -it --rm --name week1-process busybox sh
```

컨테이너 안에서 실행한다.

```sh
echo $$
ps
ls /proc
sleep 100
```

이 구성에서는 셸이 내부 PID 1이다. 터미널 B의 호스트에서 같은 컨테이너의 프로세스를 조회한다.

```bash
host_pid=$(docker inspect -f '{{.State.Pid}}' week1-process)
ps -o pid,ppid,comm -p "$host_pid"
docker top week1-process -eo pid,ppid,comm
sudo cat "/proc/$host_pid/status" | grep NSpid
```

`docker top`은 호스트 기준 PID를 보여준다. `NSpid`에서는 호스트와 내부 namespace 기준 PID를 비교할 수 있다. 셸뿐 아니라 실행 중인 `sleep`도 호스트에서 찾을 수 있다.

같은 프로세스가 서로 다른 PID로 보이는 것은 PID namespace가 번호 공간을 나누기 때문이다. 컨테이너는 별도의 커널을 부팅하지 않고 호스트의 Linux 커널을 공유한다. 확인이 끝나면 컨테이너 셸에서 `exit`으로 종료한다.

## 4. 심화 질문

### Q1. `/proc/<PID>`는 실제 저장된 파일일까?

디스크에 저장된 일반 파일이 아니다. `/proc`은 커널이 관리하는 정보를 파일 형태로 제공하는 가상 파일시스템인 procfs다. `/proc/<PID>/status`를 읽으면 해당 프로세스의 상태와 메모리 정보 등을 확인할 수 있다.

### Q2. 자식의 종료 상태를 부모가 회수해야 하는 이유는?

자식이 종료되어도 부모가 상태를 회수하기 전에는 PID와 종료 상태 등의 정보가 남는다. 이 상태가 좀비 프로세스다. 실행은 끝났지만 프로세스 테이블의 항목을 차지하므로 계속 쌓이면 문제가 된다.

부모는 `wait()` 또는 `waitpid()` 시스템 호출로 종료 상태를 회수한다.

### Q3. 호스트에서 컨테이너 프로세스가 보이는데 반대는 왜 안 될까?

PID namespace에는 계층이 있다. 상위 namespace에서는 하위 namespace의 프로세스를 볼 수 있지만, 하위에서 상위의 다른 프로세스를 PID로 식별할 수는 없다.

Docker는 내부 namespace에 맞는 procfs도 준비하므로 내부 `ps`에서는 그 범위의 프로세스가 보인다.

## 5. 정리

컨테이너도 Linux 프로세스다. 같은 커널에서 실행하되 namespace로 보이는 범위를 나누기 때문에 독립적인 환경처럼 보인다.

다음 주차에서는 이미지의 파일을 꺼내고 `chroot`로 프로세스가 사용하는 `/`를 바꾼다.
