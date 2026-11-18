# Security and privacy reports

Use [GitHub's private vulnerability report](https://github.com/davidahma/redaktr/security/advisories/new) if a selected mask exposes original pixels, an export changes the source image, the app transmits image data, or you find another security issue. The community source tree is the maintained reporting target. Include the tag or commit, macOS version, input format, affected workflow, and what you expected to happen.

Describe the problem with fictional data. A generated image or a few steps using the [sample ticket](docs/fixtures/support-ticket.png) are sufficient to begin. Keep customer screenshots, credentials, purchase information, and full diagnostic archives out of reports. The maintainer can coordinate further investigation privately.

For an ordinary detector miss or false positive on a synthetic sample, [open a public issue](https://github.com/davidahma/redaktr/issues/new/choose). Include how you corrected the selection during review.

## Privacy boundaries

Apple Vision and Redaktr's rules process the image on the Mac. The community app has a sandbox and no network entitlement. It reads images you open or paste, and can observe the image clipboard or a selected folder if you enable those features. A capture can require Screen Recording permission.

Review preferences and local history are stored on the Mac. History can include an action, date, counts, policy summary, and an output path. **Settings → Privacy → Clear History** clears those records. Exported policy files can contain sensitive custom terms and regexes. Share a fictional policy when reporting a bug.
