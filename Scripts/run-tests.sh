#!/bin/zsh
# Runs every Declutter test on a fresh iPhone simulator, one phase at a time.
#
#   Scripts/run-tests.sh                 # all phases
#   PHASES="unit ui" Scripts/run-tests.sh
#   PHASES=feature FEATURE_TESTS="DeclutterTests/BlurDetectorTests DeclutterUITests/ToolUITests/testBlurryPhotos" \
#     Scripts/run-tests.sh               # just these tests, on the standard library
#
# Phases: unit, ui, permissions (ask → denied → granted), empty, unique, large, feature.
# Each phase erases the simulator, seeds it with `xcrun simctl addmedia`, sets permissions with
# `xcrun simctl privacy`, then runs only the tests for that phase.
# Results: build/tests/results/<phase>.xcresult, logs in build/tests/logs.

set -uo pipefail
ROOT="${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
WORK="$ROOT/build/tests"
DERIVED="$WORK/DerivedData"
BUNDLE="com.dhruv.Declutter"
DEVICE_NAME="Declutter Test iPhone"
PHASES=(${=PHASES:-unit ui permissions empty unique large})
LARGE_COUNT="${LARGE_COUNT:-1500}"
typeset -A RESULTS

mkdir -p "$WORK/logs" "$WORK/results"
say() { print -P "%F{cyan}▶ $*%f" }

# MARK: Simulator

# Newest iOS runtime, and the first iPhone it supports (Pro, not Max/Plus).
read RUNTIME DEVICE_TYPE < <(xcrun simctl list runtimes available -j | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
if runtimes:
    runtime = runtimes[-1]
    phones = [t for t in runtime["supportedDeviceTypes"]
              if t["name"].startswith("iPhone") and "Max" not in t["name"] and "Plus" not in t["name"]]
    print(runtime["identifier"], phones[0]["identifier"])')
[[ -z "${RUNTIME:-}" ]] && { print "No iOS simulator runtime. Install one: xcodebuild -downloadPlatform iOS"; exit 1 }

for old in $(xcrun simctl list devices -j | python3 -c "
import json, sys
for devices in json.load(sys.stdin)['devices'].values():
    for d in devices:
        if d['name'] == '$DEVICE_NAME': print(d['udid'])"); do
  xcrun simctl delete "$old" 2>/dev/null
done
UDID=$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME")
say "Simulator $DEVICE_NAME ($DEVICE_TYPE, $RUNTIME): $UDID"

fresh_device() {
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1
  xcrun simctl erase "$UDID"
  xcrun simctl boot "$UDID"
  xcrun simctl bootstatus "$UDID" -b >/dev/null
  empty_photo_library
}

# New simulators come with a few sample photos. Remove them so each phase starts from a known library.
empty_photo_library() {
  local media="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Media"
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1
  rm -rf "$media/DCIM" "$media/PhotoData"
  xcrun simctl boot "$UDID"
  xcrun simctl bootstatus "$UDID" -b >/dev/null
}

seed() {
  local media="$WORK/media-$1"
  local files=("$media"/photos/*(N) "$media"/screenshots/*(N) "$media"/videos/*(N))
  if (( ${#files} )); then
    # addmedia handles a few hundred files per call comfortably.
    for ((i = 1; i <= ${#files}; i += 200)); do
      xcrun simctl addmedia "$UDID" "${files[@]:$((i - 1)):200}"
    done
  fi
  [[ -s "$media/contacts.vcf" ]] && xcrun simctl addmedia "$UDID" "$media/contacts.vcf"
  sleep 5  # let Photos finish importing
  say "Seeded $1: ${#files} media files"
}

install_app() { xcrun simctl install "$UDID" "$APP" }
permissions() { # grant|revoke|reset
  if [[ "$1" == reset ]]; then
    xcrun simctl privacy "$UDID" reset all "$BUNDLE"
  else
    xcrun simctl privacy "$UDID" "$1" photos "$BUNDLE"
    xcrun simctl privacy "$UDID" "$1" contacts "$BUNDLE"
  fi
}

run() { # phase, tests…
  local phase="$1"; shift
  local only=("${@/#/-only-testing:}")
  rm -rf "$WORK/results/$phase.xcresult"
  say "Running $phase: $*"
  TEST_RUNNER_DECLUTTER_PHASE="$phase" xcodebuild test-without-building \
    -project "$ROOT/Declutter.xcodeproj" -scheme Declutter \
    -destination "id=$UDID" -derivedDataPath "$DERIVED" \
    -resultBundlePath "$WORK/results/$phase.xcresult" "${only[@]}" \
    > "$WORK/logs/$phase.log" 2>&1
  local code=$?  # (\$status is reserved in zsh)
  grep -E "(Test Case|Test ).*(passed|failed|skipped)|✔|✘|error:|\*\* TEST" "$WORK/logs/$phase.log" | grep -v "^$" | tail -60
  RESULTS[$phase]=$([[ $code -eq 0 ]] && print PASSED || print "FAILED (see build/tests/logs/$phase.log)")
}

# MARK: Build and test data

say "Building for testing"
xcodebuild build-for-testing -project "$ROOT/Declutter.xcodeproj" -scheme Declutter \
  -destination "id=$UDID" -derivedDataPath "$DERIVED" > "$WORK/logs/build.log" 2>&1 \
  || { tail -30 "$WORK/logs/build.log"; exit 1 }
APP=$(find "$DERIVED/Build/Products" -path "*iphonesimulator*" -name "Declutter.app" -maxdepth 2 | head -1)

say "Generating test media"
swiftc -O "$ROOT/Scripts/generate-test-media.swift" -o "$WORK/generate-test-media" 2>/dev/null
for profile in standard unique; do "$WORK/generate-test-media" "$WORK/media-$profile" "$profile"; done
[[ " ${PHASES[*]} " == *" large "* ]] && "$WORK/generate-test-media" "$WORK/media-large" large "$LARGE_COUNT"

# MARK: Phases

for phase in $PHASES; do
  case $phase in
    unit)
      fresh_device; seed standard; install_app; permissions grant
      run unit DeclutterTests ;;
    ui)
      fresh_device; seed standard; install_app; permissions grant
      run ui DeclutterUITests/CategoryFlowUITests ;;
    permissions)
      fresh_device; seed standard; install_app; permissions reset
      run permissions-ask DeclutterUITests/PermissionUITests/testFirstLaunchAsksForAccess
      permissions revoke
      run permissions-denied DeclutterUITests/PermissionUITests/testDeniedAccessNeverCrashes
      permissions grant
      run permissions-granted DeclutterUITests/PermissionUITests/testGrantedAccessShowsContent ;;
    empty)
      fresh_device; install_app; permissions grant
      run empty DeclutterUITests/EdgeCaseUITests/testEmptyLibrary ;;
    unique)
      fresh_device; seed unique; install_app; permissions grant
      run unique DeclutterUITests/EdgeCaseUITests/testZeroDuplicates ;;
    large)
      fresh_device; seed large; install_app; permissions grant
      run large DeclutterUITests/EdgeCaseUITests/testLargeLibrary ;;
    feature)
      # Only the named tests, on the standard library with access granted (UI tests see phase "ui").
      fresh_device; seed standard; install_app; permissions grant
      RESULTS[feature]=""
      run ui ${=FEATURE_TESTS:?Set FEATURE_TESTS to the tests to run}
      RESULTS[feature]=${RESULTS[ui]}; unset "RESULTS[ui]" ;;
  esac
done

print; say "Summary"
failed=0
for phase in ${(ok)RESULTS}; do
  print "  $phase: ${RESULTS[$phase]}"
  [[ "${RESULTS[$phase]}" == PASSED ]] || failed=1
done
exit $failed
