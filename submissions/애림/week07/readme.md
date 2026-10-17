# 도커 없이 컨테이너 만들기

<img src="img/01-house.webp" width="210" align="right">

컨테이너 스터디 7주차 과제. 1~6주차에 손으로 치던 명령을 스크립트 하나로 묶었다.

명령어만 따라 치니까 다음 주에 다 까먹어서, 실습 사이트도 같이 만들었다. 비유는 리락쿠마로 잡았다. 집 짓는 얘기로 바꾸니 설명하기가 훨씬 수월했다.

**[실습 사이트 열기](https://aerim-choi.github.io/lets-make-container-study/lets-make-container-study/)**

<br clear="right">

| 파일 | 설명 |
|---|---|
| `makecontainer.sh` | 이미지 이름을 받아 컨테이너를 실행 |
| `compare.sh` | 도커 컨테이너와 같은 항목으로 비교 |
| `index.html` | 명령어를 직접 쳐보는 실습 사이트 |

## 실행

```bash
chmod +x makecontainer.sh compare.sh
sudo ./makecontainer.sh busybox:latest -- /bin/sh
```

기존 `tmproot` 가 있는 디렉터리에서는 `--workdir /tmp/run1`. 이미 있는 디렉터리는 덮어쓰지 않고 그냥 종료한다.

실행하면 8단계로 집이 지어지고 단계마다 몇 주차 내용인지 찍힌다. 그림이 거슬리면 `--quiet`.

```
   ʕ •ᴥ• ʔ   집 지으러 왔습니다

[1/8] 가구 트럭 도착   2주차 · rootfs 꺼내기
[2/8] 투명 덮개 재단   6주차 · upper / work / merged
[3/8] 계량기 설치     4주차 · cgroup v2
[4/8] 벽 세우기       3주차 · mount uts pid ipc
[5/8] 덮개 씌우기     6주차 · OverlayFS
[6/8] 이사 완료       4주차 · pivot_root + put_old 분리
[7/8] 가족 명부 비치   1주차 · procfs
[8/8] 입주           1주차 · exec, 여기서 PID 1
```

## 구조

<img src="img/02-work.webp" width="190" align="right">

```
부모(호스트)                     자식
  docker export → tmproot       [2주차]
  upper/work/merged 생성        [6주차]
  cgroup + memory.max           [4주차]
  cgroup 등록 후 ──────────▶  unshare (mount/uts/pid/ipc)  [3주차]
  wait                          mount -t overlay → merged   [6주차]
                                pivot_root merged           [4주차]
                                mount -t proc /proc         [1주차]
                                exec  ← 여기서 PID 1
  cgroup 삭제 / 디렉터리 삭제  ◀── 종료
```

<br clear="right">

적다 보니 **배운 순서랑 짓는 순서가 다르다.** 6주차 OverlayFS 준비가 두 번째고 4주차 `pivot_root` 가 여섯 번째다.

부모와 자식을 나눈 이유도 분명했다. cgroup 등록에는 자식의 호스트 PID 가 필요한데 자식은 새 PID namespace 안이라 자기 번호를 모른다. 반대로 mount 는 새 namespace 안에서만 할 수 있다. 그리고 제한이 걸리기 전에 명령이 시작되면 안 되니 `echo $$ > cgroup.procs` 후에 `exec` 한다.

## 막혔던 것

<img src="img/10-sad.webp" width="190" align="right">

**`rm -rf` 가 `Device or resource busy`.** 호스트에서 overlay 를 mount 했더니 자식이 끝나도 mount 가 남았다. 자식의 mount namespace 안에서 mount 하도록 옮기니 해결.

**`pivot_root` 다음 줄에서 command not found.** 루트가 바뀌면 호스트의 `/usr/sbin/umount` 가 사라진다. `export PATH=...` 와 `hash -r` 을 둘 다 해야 했다.

<br clear="right">

**그림이 5단계부터 안 나왔다.** `echo` 를 쓰고 있었는데 `pivot_root` 뒤에는 못 찾는다. `printf` 는 bash 내장이라 괜찮아서 전부 바꿨다.

**상자 테두리가 어긋났다.** 한글이 터미널에서 두 칸을 먹는다. 상자 안은 영문으로 바꾸고 한글은 밖에 뒀다.

## 도커와 비교

```bash
sudo ./compare.sh
```

같은 검사 항목을 양쪽에서 돌려 나란히 출력한다.

**같은 것** — PID / UTS / mount namespace, cgroup. 컨테이너 안에서 PID 1 부터 시작하고 hostname 이 분리되고 자기 프로세스만 보이고 전용 cgroup 에 들어간다.

<img src="img/12-hint.webp" width="190" align="right">

**다른 것 1 — 네트워크.** 5주차에서 직접 구성해봤지만 안 넣었다. 5주차는 `ip netns` 로 이름 붙인 namespace 를 호스트에서 설정하는 방식인데 이 스크립트는 `unshare` 로 익명 namespace 를 만든다. 넣으려면 자식 PID 를 받아 `ip link set ... netns <pid>` 로 붙이고 동기화까지 추가해야 한다. 그래서 컨테이너 안에서 호스트의 `docker0` 까지 보인다.

<br clear="right">

<img src="img/11-sad2.webp" width="190" align="right">

**다른 것 2 — capability.** 제일 큰 구멍. 컨테이너 안에서 `mount -t tmpfs tmpfs /mnt` 가 **성공한다.** 도커에서는 실패한다.

namespace 를 나눠도 권한은 안 줄어든다. mount namespace 는 결과가 어디에 보일지를 정하고 `CAP_SYS_ADMIN` 은 할 수 있는지를 정한다. 둘이 별개라는 걸 이번에 알았다.

<br clear="right">

넣어보려다 포기했다. `capsh` 가 BusyBox rootfs 에 없는데 `pivot_root` 이후에는 호스트 바이너리를 못 쓴다. 실제 런타임들은 외부 명령 대신 `prctl()` 로 직접 처리한다고 한다.

## 실습 사이트

<img src="img/04-honey.webp" width="190" align="right">

명령어를 직접 쳐야 넘어가고 맞히면 해설이 뜬다. 어려우면 조각 버튼으로 순서만 맞춰도 된다.

- 1~6주차 실습, 7주차 읽기 / 실행 — 총 89단계
- **이야기** 탭 — 리락쿠마가 집 짓는 얘기로 7주 요약
- **코드** 탭 — 두 스크립트를 좌우로 놓고 비교

<br clear="right">

<img src="img/07-ok.webp" width="140"> <img src="img/09-huh.webp" width="140"> <img src="img/10-sad.webp" width="140"> <img src="img/13-weekdone.webp" width="140">

맞히면 좋아하고 틀리면 시무룩해진다. 세 번 틀리면 더 시무룩해진다.

## 주차별 대응

| 주차 | 내용 | 스크립트에서 |
|---|---|---|
| 1주차 | 프로세스, PID 1, procfs | `mount -t proc`, `exec` |
| 2주차 | 이미지에서 rootfs 꺼내기 | `docker create` / `export` |
| 3주차 | namespace | `unshare --mount --uts --pid --ipc --fork` |
| 4주차 | pivot_root, cgroup | `pivot_root`, `memory.max`, `cpu.max` |
| 5주차 | veth, bridge, NAT | 미적용 |
| 6주차 | OverlayFS, capability | `mount -t overlay` / capability 미적용 |

<img src="img/15-alldone.webp" width="200">

`docker run` 한 줄 뒤에 이게 다 들어 있었다. 직접 지어보지 않았으면 그냥 한 줄이었을 것 같다.
