# Versioning, release and rollback

- Version: `VERSION` (MAJOR.MINOR.PATCH) + `BUILD_NUMBER`; bumped together with `CHANGELOG.md` in the same commit.
- Build: `scripts/build-app.sh [debug|release]`. Release candidates: `scripts/release.sh` (needs a clean Git tree).
  It builds a universal binary (arm64 + x86_64), signs with a Developer ID Application identity (hardened runtime, secure timestamp, no entitlements),
  notarizes and staples the app and the DMG, verifies signature, Gatekeeper and the mounted DMG, and writes everything to a **new attempt directory**:
  `<output>/release/<version>/attempts/<UTC-stamp>-<commit>/`. Earlier attempts are never deleted or overwritten; each verified candidate is
  appended to `<output>/release/<version>/CANDIDATES.tsv` (attempt, version, commit, SHA-256, size, notarization submission IDs).
- Credentials stay in the Keychain (identity + `notarytool` profile); the scripts never read, print or store secrets.
- Checks: `scripts/preflight.sh` (tests, release build, codesign, bundle checks, no personal paths in shipped sources, no literal colors).
- Rollback: a published release is immutable; a correction is a new version. The download link points to the latest release, so
  rolling back means publishing a fixed higher version, or marking the faulty release as not latest. The previous DMGs stay on the release page.
