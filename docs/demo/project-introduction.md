# 짝짜꿍 소개

짝짜꿍은 식당 점주가 납품명세서·수령기록·청구서 사진을 모아 거래별 수량과 청구 금액을 비교하고, 원본 근거를 확인해 주간 정산을 승인하는 서비스입니다.

점주는 사진을 올린 뒤 판독값을 직접 검토합니다. 정산 화면에서 납품·수령·청구가 어디서 어긋났는지 원본 행과 함께 확인하고, 수정 청구를 반영한 금액을 승인 내역으로 남길 수 있습니다.

## 심사위원 시연 3단계

[배포 웹 열기](https://jjak-jjak-ggeung-frontend.vercel.app/) · [A01–A05 예시 사진 ZIP 다운로드](https://raw.githubusercontent.com/JJak-JJak-GGeung/JJak-JJak-GGeung-Frontend/b034bdd713daa5cc62279d6e2ad1641da661c847/docs/demo/A01-A05-demo.zip)

1. **첫 사진으로 시작합니다.** ZIP을 풀고 배포 웹 오른쪽 아래 **+**를 눌러 A01을 선택합니다. 첫 방문에는 등록된 점포가 없습니다. 판독 결과를 원본과 대조하고 **가온 장어식당**을 점포, **달마루 수산**을 거래처, **2026-11-09~11-15**를 정산 주로 등록해 저장합니다.
2. **주간 자료를 모아 대조합니다.** 같은 점포·거래처·정산 주에 A02(납품명세), A03(수령기록), A04(주간청구서)를 한 장씩 올립니다. 저장 전 문서 유형과 판독값을 확인하고, A03의 수령 두 행을 해당 납품 DL-A091·DL-A131에 연결해 확인합니다. 예시의 최초 청구는 **100kg·200만 원**, 확인된 수령은 **96kg**, 차이는 **4kg·8만 원**입니다.
3. **수정본을 확인하고 승인합니다.** A05를 수정청구서로 올려 A04를 대체하는 문서로 확인합니다. 원본의 수량 합의 문구와 **192만 원**을 확인한 뒤 승인하고 **승인 내역**에서 열어봅니다.

세 단계는 같은 기기와 브라우저 프로필에서 이어서 진행합니다. 첫 화면의 **합성 명세표로 연습**으로 사진 등록 화면을 먼저 체험할 수도 있습니다.

## 저장소

[Frontend](https://github.com/JJak-JJak-GGeung/JJak-JJak-GGeung-Frontend) · [Backend](https://github.com/JJak-JJak-GGeung/JJak-JJak-GGeung-Backend) · [Database](https://github.com/JJak-JJak-GGeung/JJak-JJak-GGeung-Database)

Flutter Web 화면은 Vercel에 배포됩니다. FastAPI가 사진 판독과 거래 대조를 처리하고, Supabase PostgreSQL과 Storage가 원본·확인 이력·승인본을 보관합니다.
