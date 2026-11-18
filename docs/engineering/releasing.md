# Releasing Redaktr

GitHub is the source of truth for public releases. Versioned artifacts are published once under a tag. A release can contain source only while a signed installer is unavailable.

## Verify the source candidate

1. Update the app version and build number in [project.yml](../../Apps/macOSApp/Redaktr/project.yml), regenerate the project with XcodeGen, and update the [changelog](../../CHANGELOG.md).
2. Confirm that the required macOS check passed on the exact intended commit. Use **Actions → CI → Run workflow** with **Run the full isolated UI suite** selected for the release candidate.
3. Create the version tag from that commit and confirm the tag resolves to it on GitHub. Create the release with notes that describe the version and availability.

## Produce the signed installer

The maintainer needs Xcode, a Developer ID Application identity, and a working `notarytool` Keychain profile. Keep the identity and profile in the maintainer Keychain. The workflow for pull requests has read-only repository permissions and needs neither credential.

From an exact, clean release tag checkout, run the packaging script with the full certificate identity. The default Keychain profile is `REDAKTR_NOTARY_PROFILE`.

```sh
REDAKTR_DEVELOPER_ID='Developer ID Application: Your Name (TEAMID)' \
  Scripts/package_release.sh v0.2.0
```

The script checks CI on that commit, builds a universal app, verifies its sandbox entitlements, and validates the notarized, stapled DMG. On a clean macOS installation, open the DMG and smoke-test import, review, copy and export. Confirm that the opened app has the expected version and can export offline. Include an Intel and Apple Silicon check when both are available.

Upload the versioned DMG and `SHA256SUMS` to the GitHub release. Download both anonymously and run `shasum -a 256 -c SHA256SUMS`. Verify the downloaded DMG with Gatekeeper. Update the release notes with the installer link only once those checks pass. If an installer is withdrawn, explain why on its release and publish a new version for the correction.

The previous direct-sale update feed is a separate channel. The [migration guide](../product/migration.md) covers side-by-side use and settings transfer.
