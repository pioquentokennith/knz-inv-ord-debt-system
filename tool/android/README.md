# Release notification regression

`NotificationReleaseProbe.java` executes the notification plugin **from the
minified APK**, on an Android device. It supplies an in-memory `Context` with
synthetic preferences. It never opens the installed application's sandbox,
initializes Firebase, posts notifications, installs an APK, or clears app data.

This covers a failure invisible to mocked Flutter tests: R8 removing the generic
signature of the plugin's Gson `TypeToken`. The affected release can read a fresh
cache, but throws when reading even a saved empty `[]`. Cancellation and Retry
both encounter this cache, so repeating them cannot fix the release packaging.

## Run (PowerShell, project root)

Build the release normally with the project's private signing configuration, then
run the probe against that exact APK:

```powershell
flutter build apk --release
./tool/android/check_notification_release.ps1 -Serial YOUR_ADB_SERIAL -JavaHome 'PATH_TO_ANDROID_STUDIO/jbr'
```

To reproduce against a previous artifact, pass `-Apk 'PATH_TO_OLD_APK'`.
The script requires the Android SDK (defaults to `%LOCALAPPDATA%/Android/sdk`) and
a Java SDK. It copies only probe/artifact files to its own `/data/local/tmp`
directory, removes those remote files afterward, and retains the host log.

Expected output is four `PASS:` lines for fresh cache, saved empty cache,
three scheduled-reminder serialization cycles, and cleared cache. Any exception,
missing PASS line, or nonzero process exit fails the check. Reflection references
the plugin's current cache methods; update the probe if a future plugin upgrade
changes those methods.

This verifies actual release serialization on Android. Notification delivery,
permissions, tap navigation, and app UI must additionally be checked in the
installed app. The widget regression in
`test/screens/notification_retry_test.dart` covers the Retry button, retained
failure state, successful recovery, and avoiding duplicate stock alerts.
