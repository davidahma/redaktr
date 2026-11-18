# Detector quality

For a support screenshot, ask three questions. Did OCR read the sensitive string? Did the policy select the right span? Did the exported pixels cover it while preserving the neighboring diagnostic details? These checks exercise different parts of the app.

| Evidence | What it measures | How to interpret it |
| --- | --- | --- |
| [Detector fixture corpus](../../Packages/RedaktrCore/Tests/RedaktrCoreTests/DetectorFixtureCorpusTests.swift) | Rule matches on supplied text observations and mappings from supplied visual observations. Checks expected categories, safe negatives, near misses, box precision, and eligibility for automatic output. | Boxes and text are supplied to the test. A passing result is evidence about this synthetic corpus. |
| [OCR tests](../../Packages/RedaktrCore/Tests/RedaktrCoreTests/OCRTextRecognizerTests.swift) and [visual detector tests](../../Packages/RedaktrCore/Tests/RedaktrCoreTests/VisualSensitiveContentDetectorTests.swift) | Vision invocation and selected observation/geometry behavior on the covered inputs. | macOS version, scale, contrast, text size, and layout can affect results. |
| [Raster corpus](../../Packages/RedaktrCore/Tests/RedaktrCoreTests/VisionCorpusTests.swift) | Real Vision processing on generated support text and a QR image, followed by masking, decoding the exported image, and checking hidden and preserved regions. | Exercises the supplied layouts and categories. Dark themes, tiny fonts, varied faces, and unfamiliar layouts need their own cases. |
| [Renderer tests](../../Packages/RedaktrCore/Tests/RedaktrCoreTests/RedactionRendererTests.swift) | Pixel replacement, opaque fill, coordinate placement, and removal of source metadata when creating PNG and JPEG outputs. | A renderer can only cover the regions it receives. |
| [Support-ticket walkthrough](../fixtures/README.md) | A person checks a known image, corrects the mask selection, and reopens the output. | A walkthrough exercises one task with one input. |

Run the rule scorecard from the repository root. It prints the current numerator and denominator for each category and lists the synthetic fixture errors.

```sh
swift test --package-path Packages/RedaktrCore --filter DetectorFixtureCorpusTests/testDetectorFixtureScorecardMeetsReleaseGate
```

Report category-specific counts, the input type, and the macOS version when sharing results. Detection rates on the regression suite should be described as fixture results. For evidence about actual support work, compare reviewed exports against independent labels using the [support-team pilot](evaluation.md).
