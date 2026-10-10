# 6주차 오버레이 파일시스템과 capability
## 오버레이 파일시스템은 이미지 "중복문제"를 해결한다.
<img width="812" height="433" alt="image" src="https://github.com/user-attachments/assets/ae44489a-57f8-40ca-ba98-6259ae76a0ea" />
<img width="752" height="360" alt="image" src="https://github.com/user-attachments/assets/32b0dd46-8f0c-4ec8-a275-a7fa3d6dcd97" />

- 여러 이미지 레이어를 하나로 마운트
- Lower 레이어는 ReadOnly
	- 도커 레포지토리에서 다운받는 부분
- Upper레이어는 Writable
	- 컨테이너 레이어
		- 컨테이너 올라올때 컨테이너 안에서 변경이 발생할 수 있어 새로 올린다. 
- CoW, copy-on-write(원본유지)
	- Lower Layer가 수정하면 Merged View에서 Upper Layer가 수정하면 UpperLayer가 보이게됨
    - <img width="787" height="433" alt="image" src="https://github.com/user-attachments/assets/9647789b-6569-4f05-a670-3006fef6c5b3" />


## capability
- Linux는 root의 관리자 권한을 여러 항목으로 나눠서 프로세스에 부여합니다.
- 이 항목 하나하나가 **capability**입니다.
- 프로세스가 가진 capability 목록을 “이 프로세스에 허용된 관리자 작업 목록”으로 생각하면 됩니다. 컨테이너 전용 기능은 아니며, Docker도 이 Linux 기능으로 컨테이너 안의 프로세스 권한을 제한합니다.


## 심화질문

1. image 명을 받아 컨테이너를 실행할 수 있도록 스크립트를 만들어서 제출해주세요! (네트워크 같은 것들은 너무 복잡해질 수 있어 제외해도 좋습니다)
   - 다음주에 마저 하겠습니다...
3. 그림의 `file2`가 lowerdir와 upperdir에 모두 있을 때 어느 파일을 읽을까요? 이 실습에서 원본 `tmproot`를 직접 `/`로 사용하면 무엇이 달라질까요?
   - 답: copy-on-write(원본유지)에 의해서 upperdir에 있는 파일을 읽는다.
   - 답: tmproot가 내용이 훼손된다(원본이 훼손). 실습에서는 tmproot를 lowerdir에 두었기 때문에 훼손되지 않았던 것이다. (copy-up방식)
4. 셸을 종료하는 것, OverlayFS를 unmount하는 것, upper를 삭제하는 것은 파일 변경분에 각각 어떤 영향을 줄까요?
   - 답: <img width="834" height="221" alt="image" src="https://github.com/user-attachments/assets/00dea03d-a69d-4045-a0a7-22d885bb3845" />
   - 셋 다 "없애는 것"인 줄 알았는데 앞의 둘은 파일을 건드리지도 않았다. 셸 종료는 프로세스만 끝내고 변경분은 upper에 남아서, 다시 실행하니 file2가 changed 그대로였다. unmount는 합쳐 보여주던 화면만 걷어내는 거라 upper 파일은 멀쩡했고 다시 mount하니 복원됐다. 변경분이 실제로 사라지는 건 upper를 지울 때뿐이다.
   - 헷갈렸던 건 upper를 지우니 삭제했던 file3이 되살아난 점이다. lower가 읽기 전용이라 rm이 실제 삭제가 아니라 upper에 "없는 걸로 치라"는 표시(whiteout)를 남긴 것이었고, upper를 지우면 그 가리개가 없어져 원래 파일이 드러난다.
   - Docker로 치면 셸 종료가 docker stop, upper 삭제가 docker rm, lower가 이미지다. Dockerfile에서 RUN rm으로 지워도 이미지가 안 작아지는 이유도 같다.
6. namespace와 OverlayFS를 적용한 스크립트는 프로세스의 자원 사용량과 특권도 제한할까요? 각각 어떤 기능이 더 필요할까요?
   - 답 : 아니다.  프로세스 자원 사용량은 cgroub, 특권 제한은 이번주에 배운 capability를 사용해서 프로세스에 허용할 관리자 작업을 제한한다. 
	 
    


