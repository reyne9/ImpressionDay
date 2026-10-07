# 하루의 인상

Dart/Flutter로 만든 개인용 macOS 앱입니다. 하루 또는 여러 날에 걸친 일정을 직접 입력하면 시작 전 D-day, 진행 중 몇 일차인지, 종료 후 D+가 표시됩니다. 모네·피사로·마네·르누아르·세잔의 그림과 말을 날짜별로 한 점·한 문장씩 보여 주고, 그림을 JPEG로 저장할 수 있습니다.

## 실행

macOS 13 이상과 Flutter SDK, Xcode가 필요합니다.

```bash
flutter pub get
flutter build macos --release
open build/macos/Build/Products/Release/ImpressionDay.app
```

빌드한 `ImpressionDay.app`을 `응용 프로그램` 폴더로 옮겨 실행하는 편이 좋습니다. 앱의 설정(톱니바퀴)에서 **Mac 로그인 시 자동 실행**을 켜고 **알림 권한 요청**을 누르면, 오전 8시 알림과 하루 첫 사용 창 표시를 사용할 수 있습니다. 앱 창을 닫아도 백그라운드에서 실행됩니다. 완전히 종료하려면 메뉴 막대의 `ImpressionDay > 종료`를 누르세요.

일정은 앱의 Application Support 폴더에 저장됩니다. 그림은 [클리블랜드 미술관 공개 API](https://openaccess-api.clevelandart.org/)에서 CC0로 표시된 작품만 가져오며, 마지막 그림은 오프라인을 위해 캐시에 남깁니다. 화가의 말은 원문을 한국어로 의역했으며 각 문장의 `출처` 버튼에서 자료를 확인할 수 있습니다. 최초 그림을 불러올 때는 인터넷 연결이 필요합니다.

```bash
flutter test
dart analyze lib
```
