# Sample support ticket

[support-ticket.png](support-ticket.png) is a 920 × 348 pixel fictional support ticket drawn from the [editable SVG](support-ticket.svg). It contains no customer screenshot or genuine contact data. Use the PNG to try Redaktr. The SVG is the generator input.

For this exercise the reviewer has two instructions. Cover the requester email (`casey@example.org`) and client IP (`192.0.2.14`). Leave the subject, ticket number, field labels, and reproduction steps readable. Reopen the saved image and inspect both requirements. [support-ticket-cleaned.png](support-ticket-cleaned.png) was produced by running the community core’s actual OCR and text detector on this PNG, selecting the email and IP suggestions, and rendering both through its PNG export path. Detection suggestions can vary with local settings and the macOS Vision version.

To regenerate the image on a Mac, run the following from the repository root.

```sh
sips -s format png docs/fixtures/support-ticket.svg --out docs/fixtures/support-ticket.png
```

Use the [contribution guide](../../CONTRIBUTING.md#add-a-detector-case) to turn a different synthetic example into a regression test.
