# Screenshot redaction boundaries

The sensitive assets are the original pixels, recognized text, local policies, and the identity and path of each file. The user decides what may be shared. A finding is a suggestion that a region may need a mask. The final artifact is the PNG or JPEG the receiving application opens.

| Boundary | What can go wrong | Controls and what to check |
| --- | --- | --- |
| File, capture, or clipboard → working image | Orientation or scale changes the apparent position of a finding. A different clipboard image can arrive during a scan. | Use one upright pixel coordinate space, check the image being reviewed, and bind any automatic replacement to the clipboard item that was scanned. Test asymmetric images and two successive clipboard items. |
| Working image → proposed masks | OCR misses text or returns an incomplete bound. A category setting suppresses a finding. A detector failure can resemble a genuinely empty result. | Preserve scan failures separately from completed scans. Display findings and reasons. Review the full image and add a manual mask when needed. Check both positive examples and nearby text that must stay readable. |
| Selections → final bitmap | Opaque bars drawn on a preview fail to cover the same pixels in the saved file. Input metadata can identify the source or location. | Render accepted regions into a new pixel buffer. Use the encoded export for regression checks, inspect pixels at mask edges, and check metadata on both PNG and JPEG output. |
| Rendered bytes → destination | A file name or an alias can identify the original. A batch may encounter an existing destination partway through. Another app may keep clipboard history. | Preserve source files and existing output. Check destination identity and retry behavior. Treat clipboard replacement as a local side effect. An export does not revoke any copy another app already holds. |
| Settings, history, capture, and permissions | A portable policy includes confidential terms. A notification, local history record, or folder path can disclose context. Screen capture can include surrounding material. | Inspect imported rules and active exceptions. Check the folder and capture region. Keep policy files private. Review notification previews in macOS and clear local history when appropriate. |
| Source → installed binary | A binary with a familiar name may differ from the reviewed source or carry extra entitlements. | Build from a known tag. For a maintainer binary, check the published digest, signing identity, and notarization evidence for that exact artifact. Source builds use local ad hoc signing. |

## Limits of protection

Redaktr prepares a copy for sharing. It has no authority over the recipient, source file, clipboard manager, synchronization software, or other copies. A name, chart, face, or internal term can reveal information even when every recognized string is covered. An unlocked or compromised Mac can expose originals and local settings. The workflow relies on someone who understands the content reviewing the actual output.

[Report a security or privacy issue privately](../../SECURITY.md).
