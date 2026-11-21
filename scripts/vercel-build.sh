#!/bin/sh
set -eu
FLUTTER_VERSION=3.47.7
git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git /tmp/jjak-flutter
export PATH="/tmp/jjak-flutter/bin:$PATH"
flutter config --no-analytics
flutter pub get
flutter build web --release --dart-define=API_BASE_URL=https://jjak-jjak-ggeung-a1.rkrbhm0ryexya.ap-northeast-2.cs.amazonlightsail.com
