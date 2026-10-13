#!/usr/bin/env bash
set -euo pipefail

release_version="$1"
generator="swift-create-xcframework/.build/release/swift-create-xcframework"

build_framework() {
  local product="$1"
  shift

  "$generator" \
    "$product" \
    --platform ios \
    --platform maccatalyst \
    --platform macos \
    --platform tvos \
    --platform watchos \
    --platform visionos \
    --skip-binary-targets \
    --stack-evolution \
    --xc-setting DEFINES_MODULE=1 \
    --xc-setting "MARKETING_VERSION=$release_version" \
    --xc-setting "CURRENT_PROJECT_VERSION=$release_version" \
    --xc-setting "LD_RUNPATH_SEARCH_PATHS=@executable_path/Frameworks @loader_path/Frameworks /usr/lib/swift" \
    "$@" \
    --zip
}

build_framework AmplitudeCore
build_framework AmplitudeCoreNoUIKit --xc-setting AMPLITUDE_DISABLE_UIKIT=1

temporary_directory="$(mktemp -d)"
trap 'rm -rf -- "$temporary_directory"' EXIT
unzip -qo AmplitudeCore.zip -d "$temporary_directory"
unzip -qo AmplitudeCoreNoUIKit.zip -d "$temporary_directory"

found=0
inspected=0
while IFS= read -r binary; do
  if file "$binary" | grep -q Mach-O; then
    inspected=$((inspected + 1))
    if otool -l "$binary" | grep -q '\.xctoolchain'; then
      echo "toolchain rpath still present in $binary" >&2
      found=1
    fi
  fi
done < <(find "$temporary_directory" -type f -path '*.framework/*')

if [ "$inspected" -eq 0 ]; then
  echo "no Mach-O binaries found in AmplitudeCore xcframework slices" >&2
  exit 1
fi
if [ "$found" -ne 0 ]; then
  exit 1
fi

unzip -qo AmplitudeCore.zip
pod lib lint

update_checksum() {
  local artifact="$1"
  local checksum
  checksum="$(xcrun swift package compute-checksum "$artifact")"

  for manifest in Package.swift Package@swift-5.9.swift Package@swift-6.2.swift Package@swift-6.4.swift; do
    sed -i '' -E "/${artifact}/,/checksum:/ s/(checksum: \")[^\"]*(\")/\1$checksum\2/" "$manifest"
  done
}

update_checksum AmplitudeCore.zip
update_checksum AmplitudeCoreNoUIKit.zip
