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
# Build first, then stop Gradle/Kotlin daemons so the emulator keeps enough host memory.
build_args=(); for a in "${args[@]}"; do case "$a" in --driver=*|--target=*|-d|emulator-5554) ;; *) build_args+=("$a");; esac; done
flutter build apk --debug --target=integration_test/e2e_test.dart "${build_args[@]}" || exit 1
(cd android && ./gradlew --stop >/dev/null 2>&1 || true)
pkill -f KotlinCompileDaemon 2>/dev/null || true
free -m || true
APK=$(ls build/app/outputs/flutter-apk/app-$FLAVOR-debug.apk)
args+=(--use-application-binary "$APK" --no-enable-impeller)  # Impeller GLES crashes the emulator GPU
# Only the pixel_tablet emulator image is stable on CI runners; phone/7" layouts are produced by
# resizing its display (a real phone-sized screen and density for the app).
case "$DEVICE" in
  phone)   adb shell wm size 1080x1920; adb shell wm density 420 ;;
  tablet7) adb shell wm size 1200x1920; adb shell wm density 320 ;;
esac
adb shell wm size; adb shell wm density
adb logcat -c || true
adb logcat -v time > "../logcat-$DEVICE-$FLAVOR.txt" 2>&1 &
LOGCAT=$!
(while true; do echo "$(date +%T) host:$(free -m | awk '/Mem:/{print $7}')MB-avail guest: $(adb shell cat /proc/meminfo 2>/dev/null | head -3 | tr -s ' ' | tr '\n' ' ')" >> "../mem-$DEVICE-$FLAVOR.txt"; sleep 10; done) &
MEM=$!
mkdir -p build/screenshots
flutter drive "${args[@]}" 2>&1 | tee "../e2e-$DEVICE-$FLAVOR.log" | while IFS= read -r line; do
  case "$line" in
    *E2E_SHOT:*) name=${line##*E2E_SHOT:}; name=${name%%[[:space:]]*}
                 adb exec-out screencap -p > "build/screenshots/$name.png" && echo "captured $name" ;;
  esac
done
rc=${PIPESTATUS[0]}
# flutter drive may fail to uninstall the flavored app afterwards; the test result is what counts.
if [ $rc -ne 0 ] && grep -q "All tests passed" "../e2e-$DEVICE-$FLAVOR.log"; then rc=0; fi
kill $LOGCAT $MEM 2>/dev/null || true
exit $rc
