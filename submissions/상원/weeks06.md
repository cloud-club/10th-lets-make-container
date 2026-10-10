## 1.image 명을 받아 컨테이너를 실행할 수 있도록 스크립트를 만들어서 제출해주세요! (네트워크 같은 것들은 너무 복잡해질 수 있어 제외해도 좋습니다)
이건 고민 좀
## 2.그림의 file2가 lowerdir와 upperdir에 모두 있을 때 어느 파일을 읽을까요? 이 실습에서 원본 tmproot를 직접 /로 사용하면 무엇이 달라질까요?
owerdir와 upperdir에 동일한 file2가 존재하면 upperdir의 파일을 우선해서 읽음
원본 tmproot를 직접 루트(/)로 사용하면 파일 수정이나 삭제가 원본에 직접 반영됩니다. 반면 OverlayFS의 merged를 루트로 사용하면 변경 사항은 upperdir에 저장되고 lowerdir의 원본은 유지됩니다.

## 3.셸을 종료하는 것, OverlayFS를 unmount하는 것, upper를 삭제하는 것은 파일 변경분에 각각 어떤 영향을 줄까요?
lowerdir 에는 영향을 안주고 upper 에만 영향을 주죠 즉, 해제되면  upper 가 사라짐 

## 4.namespace와 OverlayFS를 적용한 스크립트는 프로세스의 자원 사용량과 특권도 제한할까요? 각각 어떤 기능이 더 필요할까요?

자원은 제한 안두다 보니 cgroups 기능이 필요 내부 프로세스의 관리자 특권을 제한하기 위해서는 Linux Capability를 사용해 불필요한 권한을 제거해야 함
