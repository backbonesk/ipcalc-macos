#!/bin/bash
# Builds a Release zip of IP Calc for a GitHub release and fills in the Homebrew cask.
#
# Everything account-specific comes from environment variables, so nothing private is committed.
# Keep your real values in scripts/release.local.sh (git-ignored; see release.local.sh.example).
#
#   DEVELOPMENT_TEAM   Apple Developer Team ID. Without it the app is ad-hoc signed: fine for trying
#                      it on your own Mac, but the Spotlight action won't run and Gatekeeper blocks
#                      the app on other Macs.
#   SIGN_IDENTITY      Code signing identity (default: "Developer ID Application").
#   NOTARY_PROFILE     notarytool keychain profile; when set, the app is notarized and stapled.
#                      Create it once with:
#                        xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team> --password <app-specific>
#   GITHUB_REPO        owner/repo hosting the releases; when set, writes build/ip-calc.rb.
#
# See RELEASING.md for the full release process.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep 'MARKETING_VERSION' project.yml | head -1 | sed -E 's/.*"(.*)".*/\1/')
BUILD=build/release
APP="$BUILD/Build/Products/Release/IP Calc.app"
ZIP="build/IP-Calc-$VERSION.zip"

xcodegen generate --quiet
(cd IPCalcKit && swift test --quiet)

SIGN_ARGS=()
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    SIGN_ARGS=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
               CODE_SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
               OTHER_CODE_SIGN_FLAGS="--timestamp")
else
    echo "warning: DEVELOPMENT_TEAM not set, building ad-hoc signed (local use only)" >&2
fi

rm -rf "$BUILD" "$ZIP"
xcodebuild -project IPCalc.xcodeproj -scheme IPCalc -configuration Release \
    -derivedDataPath "$BUILD" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} build | grep -E "error|BUILD" || true
[[ -d "$APP" ]] || { echo "Build failed"; exit 1; }
codesign --verify --strict "$APP"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    [[ -n "${DEVELOPMENT_TEAM:-}" ]] || { echo "Notarization needs DEVELOPMENT_TEAM"; exit 1; }
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm "$ZIP"
fi

ditto -c -k --keepParent "$APP" "$ZIP"
SHA256=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

echo
echo "Version: $VERSION"
echo "Archive: $ZIP"
echo "SHA-256: $SHA256"

if [[ -n "${GITHUB_REPO:-}" ]]; then
    # Drop the template's header comment, which only applies to this repository.
    sed -e '1,/^cask /{/^#/d;}' -e "s|__VERSION__|$VERSION|" -e "s|__SHA256__|$SHA256|" \
        -e "s|__GITHUB_REPO__|$GITHUB_REPO|g" packaging/ip-calc.rb > build/ip-calc.rb
    echo "Cask:    build/ip-calc.rb (copy to Casks/ in the tap repository)"
fi
