# Contributing

Start with the [source build and sample ticket](README.md#build-and-open-the-app). The Swift package owns detection, review policy, geometry, and rendered output. The macOS app owns interactions with the user, files, capture, and the clipboard.

## Report a missed or unwanted mask

Use a fictional example you can share publicly. Describe the input format, macOS version, source tag or commit, active policy, and which regions should be hidden or kept readable. Masking errors that expose content the user explicitly selected, changes to the original image, and unexpected transfers of data belong in [private security reporting](SECURITY.md).

**Keep customer material out of GitHub.** Create the example from scratch. An image with black boxes, real logs with values replaced, or a screenshot from a private chat can still reveal context or embedded metadata. Use invented company names, example.org addresses, and documentation IP ranges. Use generated strings only for token-format tests.

## Add a detector case

1. Name the surface and the failure in everyday terms, such as “a serial number next to the requester email in a support ticket.” State the expected category and which neighboring text must stay readable.
2. For a rule change, add a positive, a safe negative, and a near miss to the [detector corpus](Packages/RedaktrCore/Tests/RedaktrCoreTests/DetectorFixtureCorpusTests.swift). Cases that involve OCR, image orientation, or output placement also need a raster test that exercises the relevant image path.
3. For a raster case, include the synthetic generator or editable source, image size and orientation, and independently chosen expected regions. State the coordinate origin and units. Check both the covered region and at least one nearby region that must be preserved. Deriving the expected box from the detector's answer hides geometry errors.
4. Exercise the case before and after the change. Describe any false positives, increased mask area, or cases that still need human review. Put the failure and its regression test in the same pull request.

The [sample support ticket](docs/fixtures/README.md) shows how to share a synthetic input, its provenance, and a review task.

## Check a change

Run the package suite from the repository root on macOS with Xcode installed.

```sh
swift test --package-path Packages/RedaktrCore
```

Run the [app build](README.md#build-and-open-the-app) after changing the editor, preferences, or macOS integrations. For changes to user interactions, include the UI test or the exact manual steps and macOS version used. Record which checks you ran in the pull request. Use the committed Xcode project for ordinary builds. When changing the project definition, regenerate it from `Apps/macOSApp/Redaktr/project.yml` using XcodeGen and include both changes.

## Submit a pull request

Explain the user-visible change, how you verified it, and the result for older preferences or files when applicable. Keep fixtures synthetic and remove private information from logs and attachments. Contributions are made under the [Apache License 2.0](LICENSE).
