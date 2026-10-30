#!/bin/bash
# check.sh: fail if this checkout breaks the ABI or API of the latest AmplitudeCore release.
#
# Baseline:  the AmplitudeCore.zip that Package.swift's binaryTarget points at (the latest release), verified
#            against the checksum recorded there.
# Candidate: this checkout, built for one slice (generic iOS device) with BUILD_LIBRARY_FOR_DISTRIBUTION=YES.
# Both are loaded from their .private.swiftinterface (public + @_spi + @usableFromInline declarations) by the
# same swift-api-digester and compared twice:
#   ABI mode  fails on "ABI breakage" errors: removed / renamed declarations, changed signatures, new protocol
#             requirements without a default
#   API mode  fails on any "API breakage" line: source-only breaks, e.g. a protocol that now requires Sendable
# An intended break: add the reported line, without "error: ", to api/breakage-allowlist.txt with a reason.
# AmplitudeCoreNoUIKit is compiled from the same sources (Sources/AmplitudeCoreNoUIKit is a symlink) and is not
# checked separately.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=.build/api
mkdir -p "$work"
fail() { echo "FAIL: $*" >&2; exit 1; }

ver=$(sed -nE 's#.*releases/download/v([0-9][^/]*)/AmplitudeCore\.zip.*#\1#p' Package.swift | head -1)
sum=$(awk '/\/AmplitudeCore\.zip"/ {f=1; next} f && /checksum:/ {gsub(/.*checksum: *"|".*/, ""); print; exit}' Package.swift)
[ -n "$ver" ] && [ -n "$sum" ] || fail "could not read the AmplitudeCore.zip binaryTarget from Package.swift"
echo "baseline v$ver, $(xcodebuild -version | head -1)"

# 1. Baseline: the released ios-arm64 slice (cached per version).
base="$work/baseline-v$ver"
if [ ! -d "$base/AmplitudeCore.xcframework/ios-arm64" ]; then
  mkdir -p "$base"
  curl -sSfL --retry 3 -o "$base/AmplitudeCore.zip" \
    "https://github.com/amplitude/AmplitudeCore-Swift/releases/download/v$ver/AmplitudeCore.zip"
  [ "$(swift package compute-checksum "$base/AmplitudeCore.zip")" = "$sum" ] \
    || fail "AmplitudeCore.zip v$ver does not match the checksum in Package.swift"
  unzip -q -o "$base/AmplitudeCore.zip" 'AmplitudeCore.xcframework/ios-arm64/AmplitudeCore.framework/*' -d "$base"
fi

# 2. Candidate: one slice. Only its interfaces are kept, so the digester loads it exactly like the release
#    framework (which ships no binary .swiftmodule).
SECONDS=0
xcodebuild build -scheme AmplitudeCore -destination 'generic/platform=iOS' -configuration Release \
  -derivedDataPath "$work/dd" BUILD_LIBRARY_FOR_DISTRIBUTION=YES > "$work/build.log" 2>&1 \
  || { tail -30 "$work/build.log"; fail "candidate build failed (log: $work/build.log)"; }
cand="$work/candidate/AmplitudeCore.swiftmodule"
mkdir -p "$cand"
cp "$work"/dd/Build/Products/Release-iphoneos/AmplitudeCore.swiftmodule/arm64-apple-ios.{swiftinterface,private.swiftinterface} "$cand/"
build_secs=$SECONDS

# 3. Dump both sides in ABI and API mode, then diagnose.
SECONDS=0
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
# Without -abort-on-module-fail the digester exits 0 and writes an empty dump when the module doesn't load,
# which would compare as "no breakage"; the grep is a second guard against that.
dump() {  # $1 = output, rest = search path and mode flags
  local out="$1"; shift
  rm -f "$out"
  xcrun swift-api-digester -dump-sdk "$@" -module AmplitudeCore -target arm64-apple-ios15.0 -sdk "$sdk" \
    -module-cache-path "$work/module-cache" -avoid-location -abort-on-module-fail -o "$out" \
    && grep -q '"moduleName": "AmplitudeCore"' "$out"
}
for mode in abi api; do
  flag=""; [ "$mode" = abi ] && flag=-abi
  dump "$work/base.$mode.json" -F "$base/AmplitudeCore.xcframework/ios-arm64" $flag \
    || fail "swift-api-digester could not load the v$ver baseline ($mode mode)"
  dump "$work/cand.$mode.json" -I "$work/candidate" $flag \
    || fail "swift-api-digester could not load the candidate ($mode mode)"
done

grep -v -E '^[[:space:]]*(#|$)' api/breakage-allowlist.txt > "$work/allowlist.txt" || true
diagnose() { xcrun swift-api-digester -diagnose-sdk -input-paths "$work/base.$1.json" -input-paths "$work/cand.$1.json" \
  -breakage-allowlist-path "$work/allowlist.txt" -compiler-style-diags "${@:2}"; }
abi_rc=0; api_rc=0
diagnose abi -abi -error-on-abi-breakage 2> "$work/abi.txt" || abi_rc=$?
diagnose api -o "$work/api.txt" 2> /dev/null || api_rc=$?

# The ABI checker also warns "is a new API without '@available'" for every addition; only errors count.
sed -E 's/^<unknown>:0: //; s/ \[#api-digester-breaking-change\]$//' "$work/abi.txt" | grep '^error:' > "$work/abi.errors" || true
grep '^API breakage:' "$work/api.txt" > "$work/api.errors" 2> /dev/null || true
n_abi=$(wc -l < "$work/abi.errors" | tr -d ' '); n_api=$(wc -l < "$work/api.errors" | tr -d ' ')
if { [ "$abi_rc" -ne 0 ] && [ "$n_abi" -eq 0 ]; } || [ "$api_rc" -ne 0 ] || [ ! -f "$work/api.txt" ]; then
  tail -5 "$work/abi.txt" >&2
  fail "swift-api-digester failed (ABI exit $abi_rc, API exit $api_rc) without reporting a breakage"
fi

cat "$work/abi.errors" "$work/api.errors"
echo "vs v$ver: $n_abi ABI, $n_api API breakage(s); build ${build_secs}s, digester ${SECONDS}s"
if [ "$n_abi" -ne 0 ] || [ "$n_api" -ne 0 ]; then
  fail "breaking change(s) against v$ver. If intended, add the line(s) above (without \"error: \") to api/breakage-allowlist.txt with a reason."
fi
echo "PASS"
