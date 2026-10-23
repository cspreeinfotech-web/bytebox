#!/usr/bin/env bash
# Runs the integration test on the booted emulator. usage: run.sh <device> <flavor>
set -o pipefail
DEVICE=$1; FLAVOR=$2
cd "$(dirname "$0")/../../mobile"
args=(--driver=test_driver/integration_test.dart --target=integration_test/e2e_test.dart
      --flavor "$FLAVOR" -d emulator-5554 --no-pub
      --dart-define=SUPABASE_URL="$SUPABASE_URL" --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_KEY"
      --dart-define=DEMO_VIEWER_EMAIL="$DEMO_VIEWER_EMAIL" --dart-define=DEMO_PASSWORD="$DEMO_PASSWORD"
      --dart-define=SHOT_PREFIX="$DEVICE")
if [ "$FLAVOR" = play ]; then
  args+=(--dart-define=PLAY_STORE=true --dart-define=ANDROID_APP_ID=com.bytebox.play)
else
  args+=(--dart-define=APK_REFERRER="$ADS_REFERRER" --dart-define=ANDROID_APP_ID=com.bytebox.app)
fi
flutter drive "${args[@]}" 2>&1 | tee "../e2e-$DEVICE-$FLAVOR.log"
rc=${PIPESTATUS[0]}
# flutter drive may fail to uninstall the flavored app afterwards; the test result is what counts.
if [ $rc -ne 0 ] && grep -q "All tests passed" "../e2e-$DEVICE-$FLAVOR.log"; then rc=0; fi
exit $rc
