#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: REDAKTR_DEVELOPER_ID="Developer ID Application: …" %s vMAJOR.MINOR.PATCH\n' "$0" >&2
    exit 2
}

tag="${1:-}"
[[ $# == 1 && "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
: "${REDAKTR_DEVELOPER_ID:?Set to the exact Developer ID Application identity in Keychain}"
profile="${REDAKTR_NOTARY_PROFILE:-REDAKTR_NOTARY_PROFILE}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

sha="$(git rev-parse --verify "$tag^{commit}")"
if [[ "$sha" != "$(git rev-parse HEAD)" || -n "$(git status --porcelain)" ]]; then
    printf 'Check out the release tag with a clean working tree.\n' >&2
    exit 1
fi
verified_full_run() {
    local run
    for run in $(gh run list --repo davidahma/redaktr --workflow ci.yml --commit "$sha" \
        --event workflow_dispatch --status success --limit 100 --json databaseId --jq '.[].databaseId'); do
        if gh api "repos/davidahma/redaktr/actions/runs/$run/jobs" \
            --jq 'any(.jobs[]; .name == "Redaktr macOS full UI" and .conclusion == "success")' | grep -qx true; then
            return 0
        fi
    done
    return 1
}

if ! verified_full_run; then
    printf 'Full UI CI must pass for the exact release commit.\n' >&2
    exit 1
fi

# Confirm that the selected Keychain profile authenticates before building.
xcrun notarytool history --keychain-profile "$profile" --output-format json >/dev/null
build="$(mktemp -d "${TMPDIR:-/tmp}/redaktr-package.XXXXXX")"
trap 'if [[ -d "$build" ]]; then find "$build" -depth -delete; fi' EXIT
project=Apps/macOSApp/Redaktr/Redaktr.xcodeproj
xcodebuild -project "$project" -scheme Redaktr -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$build/DerivedData" \
    'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
app="$build/DerivedData/Build/Products/Release/Redaktr.app"
actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[[ "v$actual_version" == "$tag" ]] || { printf 'App version does not match the tag.\n' >&2; exit 1; }
architectures="$(xcrun lipo -archs "$app/Contents/MacOS/Redaktr")"
for architecture in arm64 x86_64; do
    if [[ " $architectures " != *" $architecture "* ]]; then
        printf 'Release executable is missing %s.\n' "$architecture" >&2
        exit 1
    fi
done
codesign --force --options runtime --timestamp --sign "$REDAKTR_DEVELOPER_ID" \
    --entitlements Apps/macOSApp/Redaktr/Redaktr/Redaktr.entitlements "$app"
codesign --verify --strict --verbose=2 "$app"
codesign -d --entitlements :- "$app" >"$build/entitlements.plist"
python3 Scripts/check_local_only_entitlements.py "$build/entitlements.plist"

asset="Redaktr-$tag.dmg"
dist="$root/build/dist/$tag"
mkdir -p "$dist"
if [[ -e "$dist/$asset" || -e "$dist/SHA256SUMS" ]]; then
    printf 'Output exists. Move it aside before packaging again.\n' >&2
    exit 1
fi
mkdir "$build/staging"
ditto "$app" "$build/staging/Redaktr.app"
ln -s /Applications "$build/staging/Applications"
cp LICENSE "$build/staging/LICENSE.txt"
hdiutil create -volname Redaktr -srcfolder "$build/staging" -format UDZO "$build/$asset"
codesign --sign "$REDAKTR_DEVELOPER_ID" --timestamp "$build/$asset"
xcrun notarytool submit "$build/$asset" --keychain-profile "$profile" --wait --timeout 30m \
    --output-format json >"$build/notary.json"
status="$(/usr/bin/plutil -extract status raw -o - "$build/notary.json")"
[[ "$status" == Accepted ]] || { printf 'Apple notarization status: %s\n' "$status" >&2; exit 1; }
xcrun stapler staple "$build/$asset"
xcrun stapler validate "$build/$asset"
hdiutil verify "$build/$asset"
spctl --assess --type open --context context:primary-signature --verbose=2 "$build/$asset"
(
    cd "$build"
    shasum -a 256 "$asset" >SHA256SUMS
)
mv "$build/$asset" "$build/SHA256SUMS" "$dist/"
printf 'Verified assets: %s\n' "$dist"
