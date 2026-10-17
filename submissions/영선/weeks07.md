
# 자율주제 만들기

## 제목 : 파이썬 프로그램을 실행할수있게 해주는 컨테이너 띄우기
- Python 실행 환경이 포함된 Docker 이미지(python:3.12-slim) 활용
- 컨테이너 내부 DNS 설정을 통해 외부 API 통신 지원
- Python으로 작성한 날씨 조회 프로그램 실행
- 파이썬 미리 설치하지 않아도 컨테이너에서 파이썬을 설치해준다

### 실행 명령어
```
sudo ./makecontainer.sh python3 -c 'print("test")'
sudo ./makecontainer.sh python3 /weather.py
```

### makecontainer.sh
```

#!/bin/bash
set -e

CMD=("$@")

mkdir -p tmproot upper work merged

# Python 실행 환경 준비 (new)
cid=$(docker create --pull=never python:3.12-slim)
docker export "$cid" | tar -C tmproot -xf -
docker rm -v "$cid"

# Python 스크립트 및 DNS 설정 (new)
cp weather.py tmproot/weather.py
cp -L /etc/resolv.conf tmproot/etc/resolv.conf

# OverlayFS 마운트
mount -t overlay overlay \
  -o lowerdir="$(realpath tmproot)",upperdir="$(realpath upper)",workdir="$(realpath work)" \
  merged

rootfs=$(realpath merged)

unshare --uts --pid --fork --mount bash -c '
  set -e
  rootfs=$1
  shift

  mount --make-rprivate /
  hostname myhost

  mkdir -p "$rootfs/put_old"
  cd "$rootfs"
  pivot_root . put_old
  cd /
  hash -r

  mkdir -p /proc
  mount -t proc proc /proc

  umount -l /put_old
  rmdir /put_old

  exec "$@"
' makecontainer-init "$rootfs" "${CMD[@]}"

```
### weather.py
```
import json
import urllib.request

url = (
    "https://api.open-meteo.com/v1/forecast"
    "?latitude=37.5665&longitude=126.9780"
    "&current=temperature_2m,relative_humidity_2m,"
    "apparent_temperature,weather_code"
    "&timezone=Asia%2FSeoul"
)

with urllib.request.urlopen(url, timeout=10) as response:
    data = json.load(response)

weather = data["current"]

codes = {
    0: "맑음",
    1: "대체로 맑음",
    2: "구름 조금",
    3: "흐림",
    45: "안개",
    61: "약한 비",
    63: "비",
    65: "강한 비",
    71: "약한 눈",
    73: "눈",
    75: "강한 눈",
    95: "뇌우",
}

print("=== 서울 현재 날씨 ===")
print(f"기온: {weather['temperature_2m']}°C")
print(f"체감 온도: {weather['apparent_temperature']}°C")
print(f"습도: {weather['relative_humidity_2m']}%")
print(f"날씨: {codes.get(weather['weather_code'], '기타')}")

```


### 참고

₩₩₩
cid=$(docker create --pull=never python:3.12-slim)
docker export "$cid" | tar -C tmproot -xf -
docker rm -v "$cid"
₩₩₩

이 부분에서 설치후 제거하는 이유 : 도커컨테이너에서 파이썬 설치된 파일시스템을 설치후 복붙한 뒤 삭제하는 것.
(파이썬 실행에 필요한 것만 tmproot에 복붙용)
