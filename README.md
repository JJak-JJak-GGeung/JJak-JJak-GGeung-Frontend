# 짝짜꿍 Frontend

짝짜꿍은 식자재를 납품받는 점주가 사진으로 올린 명세서·수령 기록·청구서를 한곳에서 대조하는 서비스입니다. 거래처와 통화한 내용은 전사 초안을 고쳐 해당 거래의 메모로 남길 수 있습니다. 점주는 차이가 난 품목과 원본을 확인하고 정산을 직접 승인합니다.

## 심사위원용 시연

[합성 예시 사진 A01~A05 다운로드](./docs/demo/jjakjjakggeung-demo-a01-a05.zip?raw=true) · [배포 앱 열기](https://jjak-jjak-ggeung-frontend.vercel.app/)

처음 방문한 브라우저에는 저장된 점포와 거래가 없습니다. 회원가입 없이 사진으로 새 점포와 거래처를 만들 수 있습니다.

1. 예시 ZIP을 풀고 배포 앱 오른쪽 아래 **+ → 사진 올리기**에서 `A02_납품명세_1113.png`를 선택합니다.
2. **원본 보기**에서 명세 번호 `DL-A131`, 첫 품목 `40kg`, 단가 `20,000원/kg`을 판독값과 대조합니다.
3. **가온 장어식당**을 내 점포로, **달마루 수산**을 거래처로 선택하거나 새로 등록합니다. **납품 명세서**, 정산 주 **2026-11-09~11-15**를 선택하고 저장한 뒤, 정산 화면에서 문서와 원본을 다시 엽니다.

수령과 청구를 연결해 차이를 확인하고 승인본까지 다시 열어보려면 [전체 시연 안내](./docs/DEMO.md)를 따라가세요. 자료는 처음 저장한 브라우저 프로필에서 다시 찾을 수 있습니다.

## 구성

| 저장소 | 역할 |
| --- | --- |
| [Frontend](https://github.com/JJak-JJak-GGeung/JJak-JJak-GGeung-Frontend) | Flutter Web 화면, 사진·통화녹음 입력, 판독값 검수, 주간 정산 조회 |
| [Backend](https://github.com/JJak-JJak-GGeung/JJak-JJak-GGeung-Backend) | FastAPI, 사진 판독과 음성 전사, 수령·청구 대조 및 승인 처리 |
| [Database](https://github.com/JJak-JJak-GGeung/JJak-JJak-GGeung-Database) | Supabase PostgreSQL 스키마, 원본 보관, 확인 이력과 승인본 저장 |

이 저장소는 Flutter 프로젝트입니다. 화면은 `lib/`, 패키지 명세는 `pubspec.yaml`에 있습니다. 로컬에서는 `flutter pub get`, `flutter test`, `flutter build web`으로 확인할 수 있습니다.
