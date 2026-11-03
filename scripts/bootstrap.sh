#!/bin/bash
# Turn this starter into a buildable project.
#
#   ./scripts/bootstrap.sh <AppName> [BundlePrefix]
#   e.g. ./scripts/bootstrap.sh Acme com.example
#
# Copies stencils/ into place, renames MyApp -> <AppName> everywhere, and points the
# Makefile seam and SwiftLint scope at the result. Afterwards `make ci` should be green
# AND non-vacuous — a starter whose gates pass by inspecting nothing is worse than none
# (ADR-SWIFT-S11 rule 6).
#
# The Xcode project it installs is not a sketch: it is the one that surfaced four
# non-obvious failures when this layout was first built for real —
#   * an empty <TestPlans> element silently disables the scheme's test action
#   * synchronized root groups sweep Info.plist and xcconfigs into Copy Bundle Resources
#     unless a PBXFileSystemSynchronizedBuildFileExceptionSet excludes them
#   * ENABLE_TESTABILITY is implicit in Xcode's template but must be stated in a
#     pure-xcconfig setup, or @testable import cannot resolve the app module
#   * @main on an NSApplicationDelegate never invokes applicationDidFinishLaunching
# Each is already handled here.

set -euo pipefail

APP_NAME="${1:-}"
BUNDLE_PREFIX="${2:-com.example}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "$APP_NAME" ]]; then
    echo "usage: ./scripts/bootstrap.sh <AppName> [BundlePrefix]" >&2
    echo "       e.g. ./scripts/bootstrap.sh Acme com.example" >&2
    exit 1
fi
if [[ ! "$APP_NAME" =~ ^[A-Za-z][A-Za-z0-9]*$ ]]; then
    echo "error: <AppName> must be alphanumeric and start with a letter (it becomes a Swift module name)" >&2
    exit 1
fi

cd "$ROOT"

if [[ -e "$APP_NAME" || -e "$APP_NAME.xcodeproj" ]]; then
    echo "error: $APP_NAME or $APP_NAME.xcodeproj already exists — refusing to overwrite." >&2
    exit 1
fi
if [[ ! -d stencils ]]; then
    echo "error: stencils/ not found. Run this from a fresh clone of the starter." >&2
    exit 1
fi

echo "==> installing project as '$APP_NAME' (bundle prefix $BUNDLE_PREFIX)"

cp -R "stencils/MyApp"            "$APP_NAME"
cp -R "stencils/MyAppTests"       "${APP_NAME}Tests"
cp -R "stencils/MyApp.xcodeproj"  "${APP_NAME}.xcodeproj"
cp -R "stencils/MyApp.xcworkspace" "${APP_NAME}.xcworkspace"

# Rename files whose names carry MyApp, deepest first so parents stay valid.
find "$APP_NAME" "${APP_NAME}Tests" "${APP_NAME}.xcodeproj" "${APP_NAME}.xcworkspace" \
     -depth -name '*MyApp*' | while read -r path; do
    mv "$path" "$(dirname "$path")/$(basename "$path" | sed "s/MyApp/${APP_NAME}/g")"
done

# Rewrite contents. MyApp -> AppName, and the placeholder bundle prefix.
find "$APP_NAME" "${APP_NAME}Tests" "${APP_NAME}.xcodeproj" "${APP_NAME}.xcworkspace" \
     -type f -print0 | xargs -0 sed -i '' \
     -e "s/MyApp/${APP_NAME}/g" \
     -e "s/com\.example/${BUNDLE_PREFIX}/g"

# Point the command facade and the linter at the new tree. These two must agree or the
# linter inspects zero files and passes vacuously — `make doctor` checks it.
sed -i '' -e "s/^APP_NAME      ?= MyApp$/APP_NAME      ?= ${APP_NAME}/" Makefile
sed -i '' -e "s/^  - MyApp$/  - ${APP_NAME}/" -e "s/^  - MyAppTests$/  - ${APP_NAME}Tests/" .swiftlint.yml

echo "==> installed:"
echo "    ${APP_NAME}/                 app sources (App, Build Configs, Supporting)"
echo "    ${APP_NAME}Tests/            test target"
echo "    ${APP_NAME}.xcodeproj        synchronized root groups — adding a file needs no project edit"
echo "    ${APP_NAME}.xcworkspace      open THIS, not the .xcodeproj"
echo
echo "==> next"
echo "    make doctor        # every line should now be present / OK"
echo "    make ci            # green AND non-vacuous"
echo "    make install-hooks # pre-commit -> fast tier, pre-push -> full tier"
echo
echo "    Then settle MACOSX_DEPLOYMENT_TARGET in ${APP_NAME}/Build Configs/Project-Base.xcconfig"
echo "    and set DEVELOPMENT_TEAM / SIGN_IDENTITY in the Makefile seam when you have a"
echo "    Developer ID Application certificate (ADR-SWIFT-S10)."
echo
echo "    stencils/ is no longer needed — delete it, or keep it to bootstrap a second target."
