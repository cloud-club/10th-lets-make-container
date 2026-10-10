# 6주차 - OverlayFS와 컨테이너 실행 통합

## 1. 이미지 원본과 변경분

이미지에서 꺼낸 파일을 그대로 rootfs로 쓰면 내부에서 수정한 내용이 그 디렉터리에 남는다. 여러 실행 환경에서 원본을 공유하려면 쓰기 영역을 나눠야 한다.

OverlayFS는 여러 디렉터리를 합쳐 하나처럼 보여주는 파일시스템이다.

| 경로 | 역할 |
| --- | --- |
| lowerdir | 원본 파일을 읽는 영역 |
| upperdir | 수정하거나 새로 만든 파일을 저장하는 영역 |
| workdir | 커널이 사용하는 작업 공간 |
| merged | lower와 upper를 합쳐 프로세스에 보여주는 마운트 지점 |

`workdir`는 처음에 비어 있어야 하고 `upperdir`와 같은 파일시스템에 있어야 한다. lower와 upper에 같은 경로가 있으면 upper 쪽이 우선한다.

## 2. OverlayFS 파일 변경 확인

기존 `tmproot`에 마운트가 남아 있지 않은 상태에서 시작한다. `upper`, `work`, `merged`와 관찰용 파일 이름도 기존 자료와 겹치지 않아야 한다.

```bash
mkdir upper work merged
printf 'original\n' | sudo tee tmproot/file1 tmproot/file2 tmproot/file3
sudo mount -t overlay overlay \
  -o lowerdir="$PWD/tmproot",upperdir="$PWD/upper",workdir="$PWD/work" \
  merged
findmnt --mountpoint merged
```

호스트에서 merged를 통해 파일을 수정한다. 컨테이너가 merged를 `/`로 쓰는 경우도 같은 파일시스템 동작을 거친다.

```bash
echo changed | sudo tee merged/file2
echo new | sudo tee merged/file4
cat tmproot/file2
sudo cat upper/file2
cat merged/file2
sudo cat upper/file4
```

기대되는 내용은 순서대로 `original`, `changed`, `changed`, `new`다. lower에 있던 파일을 처음 수정하면 upper로 복사한 뒤 변경한다. 이것이 copy-up이다. 원본 파일은 유지된다.

삭제도 원본을 직접 지우는 방식은 아니다.

```bash
sudo rm merged/file3
cat tmproot/file3
sudo ls -l upper/file3
ls merged/file3
```

원본은 남고 merged에서는 보이지 않아야 한다. upper에는 lower의 파일을 숨기는 whiteout이 생긴다. 커널과 구성에 따라 장치 파일이나 확장 속성을 가진 파일로 표현된다.

다음처럼 해제했다가 같은 upper로 다시 마운트해도 변경분은 유지된다.

```bash
sudo umount merged
sudo mount -t overlay overlay \
  -o lowerdir="$PWD/tmproot",upperdir="$PWD/upper",workdir="$PWD/work" \
  merged
cat merged/file2 merged/file4
```

확인이 끝나면 마운트를 해제한다. 해제에 성공하고 `findmnt --mountpoint merged`에 출력이 없는 것을 확인한 뒤, 이번 실습에서 만든 파일만 정리한다.

```bash
sudo umount merged
findmnt --mountpoint merged
```

```bash
sudo rm -rf upper work
rmdir merged
sudo rm tmproot/file1 tmproot/file2 tmproot/file3
```

## 3. 이미지 이름을 받는 실행 스크립트

통합 코드는 [makecontainer.sh](./makecontainer.sh)에 작성했다. Linux 실습 VM에서 Docker, util-linux, cgroup v2, OverlayFS를 사용할 수 있어야 한다. rootfs 전환 후 정리 명령에 `/bin/busybox`를 사용하므로 BusyBox 계열 이미지를 대상으로 한다.

```bash
chmod +x makecontainer.sh
sudo ./makecontainer.sh busybox:latest -- /bin/sh
```

실행 순서는 다음과 같다.

1. 이미지가 없으면 pull하고 임시 컨테이너에서 파일을 추출한다.
2. 별도 작업 디렉터리에 lower·upper·work·merged를 준비한다.
3. cgroup에 메모리 50 MiB, swap 0을 설정한다.
4. 자식이 호스트 기준 PID로 cgroup에 등록한 뒤 namespace를 만든다.
5. 자식의 mount namespace 안에서 OverlayFS를 마운트한다.
6. merged로 `pivot_root`하고 이전 루트를 분리한 뒤 procfs를 연결한다.
7. `--` 뒤의 명령을 `exec`하고, 종료 후 부모가 자원을 정리한다.

작업 경로는 `/var/tmp/makecontainer-study`다. 기존 경로가 있으면 중단하며, 정상 종료와 처리 가능한 오류에서는 이번 실행의 파일과 cgroup을 정리한다. 강제 종료나 VM 중단으로 남은 경로는 상태를 확인한 뒤 정리해야 한다.

네트워크와 IPC namespace도 나누지만 veth·bridge·NAT는 연결하지 않았다. 따라서 이 스크립트로 실행한 환경에서는 외부 통신을 기대하면 안 된다. CPU quota도 아직 적용하지 않았다.

내부에서 확인할 명령은 다음과 같다.

```sh
hostname
echo $$
ps
cat /proc/self/cgroup
mount
echo test > /sample.txt
cat /sample.txt
exit
```

종료 후 호스트에서 작업 경로와 cgroup이 남지 않았는지 확인한다.

```bash
sudo test ! -e /var/tmp/makecontainer-study && echo '작업 경로 정리됨'
find /sys/fs/cgroup -maxdepth 1 -name 'makecontainer-study-*'
```

이 통합 버전은 종료할 때 upper도 지운다. 2번 수동 실습처럼 같은 upper를 재사용하는 구성과는 달리, 다음 실행에서는 변경 파일이 남지 않는다.

## 4. 심화 질문

### Q1. 이미지 이름을 받아 실행하려면?

3번의 스크립트처럼 이미지 준비와 rootfs 실행을 연결한다. Docker는 파일 추출에만 사용하고 실제 실행은 `unshare`, `pivot_root`, `exec`로 처리한다. 이미지의 `CMD`, `ENTRYPOINT`, `ENV`, `USER`를 재현하는 기능은 넣지 않았으므로 실행 명령을 명시적으로 넘긴다.

### Q2. file2가 lower와 upper 양쪽에 있다면?

merged에서는 upper의 파일을 읽는다. lower를 직접 `/`로 사용하면 이 분리가 없어져 실행 중 수정한 내용이 원본 디렉터리에 바로 반영된다.

### Q3. 셸 종료, unmount, upper 삭제의 차이는?

셸 종료는 프로세스를 끝내는 일이고, unmount는 합쳐 보이던 파일시스템 연결을 해제하는 일이다. 둘 다 그 자체로 upper의 파일을 지우지는 않는다. 마운트를 해제한 뒤 upper를 삭제하면 저장된 변경분과 삭제 표시가 사라진다.

### Q4. namespace와 OverlayFS만으로 사용량과 특권도 제한될까?

그렇지 않다. 사용량 제한은 cgroup, 관리자 작업 권한 축소는 capability 같은 별도 기능이 필요하다. 이번 스크립트에는 메모리 제한은 있지만 capability 축소는 없다.

mount namespace를 나눠도 `CAP_SYS_ADMIN`이 남아 있으면 해당 권한 범위에서 mount 작업이 가능하다. 환경을 준비할 권한과 최종 프로그램에 넘길 권한을 구분해야 한다. user namespace, seccomp, 최소 장치 구성도 적용하지 않았으므로 신뢰하는 이미지로 개념을 확인하는 실습용이다.

## 5. 정리

컨테이너 실행은 파일 준비, 쓰기 영역 분리, namespace 구성, 루트 교체, 자원 제한을 순서대로 연결한 과정이다. 대상 프로그램을 실행하는 부분뿐 아니라 종료를 기다리고 이번 실행의 자원을 회수하는 부모 프로세스도 필요하다.

참고: [OverlayFS](https://docs.kernel.org/filesystems/overlayfs.html), [6주차 실습 가이드](../../docs/week06.md)
