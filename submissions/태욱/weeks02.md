# 2주차 - 이미지와 rootfs, chroot

## 1. 이미지와 rootfs

이미지는 실행 파일, 라이브러리, 기본 명령과 환경 변수 등의 설정을 담는다. rootfs는 프로세스가 `/` 아래에서 사용할 파일시스템이다.

이미지로 컨테이너를 만드는 것과 그 안의 프로그램을 실행하는 것은 별개다. `docker create`는 컨테이너를 준비하고, `docker start`가 프로세스를 시작한다. 이번에는 실행하지 않은 컨테이너에서 파일만 꺼낸다.

```bash
uname -a
ls /
findmnt /
sudo docker run --rm busybox sh -c 'uname -a; ls /; ls -l /bin/sh'
```

호스트와 컨테이너에서 커널 버전은 같아도 hostname이나 `/` 아래의 파일은 다를 수 있다. 같은 커널을 공유한다는 것이 같은 파일 목록까지 사용한다는 뜻은 아니다.

## 2. BusyBox 파일 꺼내기

호스트의 작업 디렉터리에서 실행한다. `tmproot`는 새로 만드는 디렉터리다.

```bash
mkdir tmproot
cid=$(sudo docker create busybox)
sudo docker export "$cid" | sudo tar -C tmproot -xf -
sudo docker rm -v "$cid"
sudo du -sh tmproot
sudo ls tmproot
sudo ls -l tmproot/bin/sh
```

`docker export`는 컨테이너 파일시스템을 tar로 내보낸다. `docker save`처럼 이미지 레이어와 실행 설정을 보관하는 명령은 아니다. 마운트된 volume의 내용도 export 대상에 포함되지 않는다.

파일을 풀었다고 컨테이너가 실행되는 것은 아니다. 지금의 `tmproot`는 호스트에 있는 디렉터리일 뿐이다.

## 3. chroot와 procfs

### 루트 디렉터리 변경

호스트의 hostname과 PID를 확인한 뒤 들어간다.

```bash
hostname
echo $$
sudo chroot tmproot /bin/sh
```

새 셸 안에서 확인한다.

```sh
pwd
cd ..
pwd
ls /
hostname
echo $$
ls /proc
ps
exit
```

`tmproot/bin/sh`가 내부에서는 `/bin/sh`다. `/`에서 `cd ..`를 해도 일반적인 경로 탐색으로 호스트의 상위 디렉터리에 나갈 수 없다.

다만 hostname이나 PID namespace를 나누지는 않았다. 셸의 PID가 달라지는 것은 새 프로세스를 실행했기 때문이지, PID namespace가 분리됐기 때문이 아니다.

### procfs 마운트 전후

export한 파일에는 실행 중인 procfs가 담기지 않는다. `/proc`이 비어 있어 `ps`가 실패하는 것은 프로세스가 격리됐다는 증거가 아니다.

호스트에서 procfs를 연결한 다음 다시 들어간다.

```bash
sudo mkdir -p tmproot/proc
sudo mount -t proc proc tmproot/proc
findmnt --mountpoint tmproot/proc
sudo chroot tmproot /bin/sh
```

내부에서 확인한다.

```sh
ls /proc
ps
exit
```

호스트와 같은 PID namespace에서 마운트했으므로 호스트 프로세스가 보인다. BusyBox와 호스트의 `ps`는 출력 형식이 다를 수 있어 PID와 명령 이름 위주로 비교한다.

실습 후에는 호스트에서 마운트만 해제한다. `tmproot`는 다음 주차에서도 사용한다.

```bash
sudo umount tmproot/proc
findmnt --mountpoint tmproot/proc
```

마지막 명령에 출력이 없으면 해당 경로의 마운트가 해제된 상태다.

## 4. 심화 질문

### Q1. 이미지, 컨테이너, tmproot는 어떤 관계일까?

이미지는 파일과 실행 설정의 바탕이고, 컨테이너는 이미지로부터 만든 실행 환경이다. `tmproot`는 그 컨테이너에서 export한 파일을 풀어놓은 디렉터리다. 여기에 `chroot`를 적용하면 셸의 rootfs로 사용할 수 있다.

### Q2. procfs를 연결하자 호스트 프로세스가 보이는 이유는?

PID namespace를 바꾸지 않았기 때문이다. 마운트 전에는 프로세스 정보를 읽을 경로가 없었을 뿐이고, 마운트 후에는 호스트 기준 정보를 읽게 된다.

### Q3. chroot를 안전한 격리 장치라고 할 수 없는 이유는?

파일 경로의 기준만 바꾸며 권한, 네트워크, PID 등을 함께 제한하지 않는다. 외부를 가리키는 열린 파일 디스크립터나 충분한 권한이 남아 있으면 경계를 벗어날 여지가 있다. `cd ..`가 막힌다는 사실만으로 완전한 격리라고 볼 수 없다.

## 5. 정리

rootfs를 준비하는 것, `/`를 바꾸는 것, 프로세스를 격리하는 것은 각각 다른 작업이다. `chroot`만 적용한 환경에 namespace를 더하는 것이 다음 단계다.
