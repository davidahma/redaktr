# Redaktr open-source launch plan

## Scope and release decisions

Publish a self-contained macOS app and its Swift package under Apache-2.0. The community build processes screenshots locally, works without credentials, and keeps import, review, capture, copy, save, and batch export available. Use the existing SwiftUI and Vision pipeline. The initial public source snapshot is derived from legacy commit `5e54d15`. The prior history and checkout remain available to the maintainer. A separate bundle identity lets the community build coexist with a prior installation.

## Implementation and acceptance

| Workstream | Change | Evidence to collect |
| --- | --- | --- |
| Review and export | Represent scan state explicitly, share eligibility across interactive output routes, distinguish partial output, and preserve source identity. | Failed or in-progress scans never silently become cleaned output. Tests cover mixed batches and destination aliases. |
| Detection and masks | Preserve distinct overlapping masks, treat incomplete character geometry as uncertain, and honor visual detector policy. | Geometry and disposition regressions plus actual Vision-to-output tests on independently marked synthetic images. |
| Clipboard | Bind automatic replacement and undo to the clipboard generation they own. | A stale scan or stale undo preserves newer clipboard contents. |
| Community configuration | Remove time-limited access, provider calls, and the legacy update feed from this build. | Build and entitlement checks, and UI coverage of import, review, and export. |
| Contributor safety | Isolate the UI test bundle, preferences, pasteboard, and outputs. | Native CI smoke tests, full UI suite on demand, and documented commands. |
| Public packaging | Publish source, license, contribution and security guidance, threat model, an original sample, and a release runbook. | Fresh checkout validation, anonymous GitHub readback, and a hosted check on the published commit. |
| Distribution | Publish signed binaries only from a validated commit and independently verify their checksums and notarization. | Provenance, signed artifact readback, and a clean-install smoke test before labeling a binary available. Treat the legacy feed and purchase migration as distinct owner tasks where account access is required. |

## Product improvements

Use a visual start and direct macOS build instructions, as [macshot](https://github.com/sw33tLie/macshot) demonstrates. Use an explicit privacy posture and a short detector review flow, as [Sealshot](https://github.com/ldeng83/Sealshot) demonstrates. Redaktr’s sample and implementation are original. Keep the first-run workflow centered on review, opaque output and custom policy terms. Start a synthetic corpus with an ordinary support screenshot, hard negatives, and a visual code. Expand reviewed cases before making comparative detection claims.

Offer a small support-engineering field trial after release. Compare residual sensitive regions, unintended masks, time to a reviewed output and repeat use against the participant's current workflow. Record synthetic evaluation and field observations as distinct evidence.

## Verification order

1. Check the committed project against XcodeGen, review release scripts, and validate source and signed entitlements.
2. Run the core suite and synthetic corpus, compile the app, and exercise the isolated UI scheme.
3. Validate support and privacy claims against the build, scan the public candidate, and inspect generated assets and links.
4. Publish the source commit, confirm the hosted check on that exact revision, and require that check on main.
5. Tag the source preview. Promote a signed, notarized binary only when its independent release checks pass.
