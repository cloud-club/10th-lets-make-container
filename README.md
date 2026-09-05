# 10th-lets-make-container

도커 없이 직접 만든 도구로 컨테이너를 만들어보면서 컨테이너 가상화에 대해 알아봅시다

[참고 자료](https://www.youtube.com/watch?v=lVtgqmjv4BQ)

## 로드맵


| 주차 | 주제                           | 결과물                             |
| ---- | ------------------------------ | ---------------------------------- |
| 1    | Linux 프로세스 실행 모델       | 호스트와 컨테이너의 프로세스 비교  |
| 2    | 이미지, rootfs, `chroot`       | rootfs와 `chroot` 관찰 기록        |
| 3    | namespace, mount, `pivot_root` | 격리 셸 실행 결과                  |
| 4    | cgroups v2                     | CPU·메모리 제한 기능               |
| 5    | 컨테이너 네트워크              | 외부 통신 가능한 network namespace |
| 6    | 기능 통합과 cleanup            | `run-container.sh`                 |
| 7    | 실행 경로 코드화               | `mydocker run`과 상태 디렉터리     |
| 8    | 생명주기 CLI와 OCI 비교        | `exec`·`ps`·`stop`·`rm` 최종 데모  |
