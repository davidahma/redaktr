#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
suite="${REDAKTR_UI_SUITE:-smoke}"
case "$suite" in
  smoke)
    set -- \
      -only-testing:RedaktrUITests/RedaktrUITests/testFreshLaunchShowsLocalOnlyFirstRunCopy \
      -only-testing:RedaktrUITests/RedaktrUITests/testFirstLaunchQuickStartCanLoadSample \
      -only-testing:RedaktrUITests/RedaktrUITests/testLaunchWithFixtureReachesReviewScreenAndExportState \
      -only-testing:RedaktrUITests/RedaktrUITests/testDirectExportWritesCleanedImageAndRecordsHistory \
      -only-testing:RedaktrUITests/RedaktrUITests/testFailedScanBlocksSharingUntilManualReview \
      -only-testing:RedaktrUITests/RedaktrUITests/testFailedBatchItemBlocksBulkExportUntilManualReview \
      -only-testing:RedaktrUITests/RedaktrUITests/testPasteImageKeyboardShortcutLoadsClipboardImage \
      -only-testing:RedaktrUITests/RedaktrUITests/testSettingsExposeCustomDetectionControls \
      "$@"
    ;;
  full) ;;
  *) printf 'Use REDAKTR_UI_SUITE=smoke or full.\n' >&2; exit 2 ;;
esac

exec xcodebuild test \
  -project "$root/Apps/macOSApp/Redaktr/Redaktr.xcodeproj" \
  -scheme Redaktr -configuration UITesting -destination 'platform=macOS' \
  -parallel-testing-enabled NO "$@"
