#!/bin/sh
set -eu
FLUTTER_VERSION=3.47.7
git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git /tmp/jjak-flutter
export PATH="/tmp/jjak-flutter/bin:$PATH"
flutter config --no-analytics
flutter pub get
: "${SUPABASE_URL:?Set SUPABASE_URL in the deployment environment}"
: "${SUPABASE_PUBLISHABLE_KEY:?Set SUPABASE_PUBLISHABLE_KEY in the deployment environment}"
flutter build web --release \
  --dart-define=API_BASE_URL=https://jjak-jjak-ggeung-a1.rkrbhm0ryexya.ap-northeast-2.cs.amazonlightsail.com \
  --dart-define="SUPABASE_URL=$SUPABASE_URL" \
  --dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"
