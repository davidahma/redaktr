# Moving from an older direct-sale build

The community edition can scan, review, copy, and export without a trial, activation, or license-server connection. The supported migration path is a source build from this repository. The community bundle has a new application identifier and its own local preferences. Keep the old app available while checking your setup.

1. In the old app, go to **Settings → Privacy** and choose **Export Settings**. Store the resulting JSON locally. This file contains policy choices and may include private custom terms, patterns, and exceptions.
2. Quit the old app so only one copy watches the clipboard or screenshot folder. Both bundles use the name `Redaktr.app`. Keep them in separate folders while checking the migration. Follow the [community build instructions](../../README.md#build-and-open-the-app).
3. In the community app's **Settings → Privacy**, choose **Import Settings** and inspect the active policy and a few custom terms. Use the [sample ticket](../fixtures/support-ticket.png) to check scan, manual review, copy, and export before working on a real image.
4. If you use folder watching, clipboard monitoring, or capture, review those settings and macOS permissions in the community app. Re-select folders when prompted.

The portable file carries detection settings. History, purchase records, Keychain entries, bookmarks, source images, and previous exports are outside its scope. Keep your existing receipt and license record privately. The community app has no in-app updater. To upgrade a source build, check out the next published tag and repeat the build instructions.
