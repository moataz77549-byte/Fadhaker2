# Build compatibility notes

- The Android release uses Flutter 3.24.5.
- `app_links` 6.4.1 expected a `flutter` Gradle extension that was unavailable in the generated platform scaffold, causing the release build to fail.
- The project pins `app_links` to 6.1.0 through `dependency_overrides`; the package archive was inspected from https://pub.dev/api/archives/app_links-6.1.0.tar.gz and uses a fixed compileSdkVersion.
- The official release workflow is `.github/workflows/android-release.yml` and targets Android ARM64 with Android 8+ minimum.
