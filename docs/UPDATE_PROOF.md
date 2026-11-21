# Update flow: proof and limits (0.6.0)

Evidence: the full transcript of the run is kept on the maintainer's external test storage (not part of the repository).

**What was run for real.** Two Developer ID–signed, notarized, stapled builds: 0.6.0 (the release candidate) and 0.6.1 (a test candidate built on a private branch, never published).
0.6.0 was installed into an isolated folder on external storage; the real `UpdateService`/`UpdateVerifier`/`UpdateInstaller` (via `gel-bench update-run`) then checked and installed 0.6.1 from the signed DMG:
1. wrong checksum → refused, 0.6.0 untouched; 2. update 0.6.0 → 0.6.1 installed (version, `codesign --verify --deep --strict`, Team ID 8AR6XP8MG7, bundle ID and `stapler validate` re-checked on the result; no leftover staging/backup folders);
3. already current → "up to date"; 4. a lower announced version is never offered (no downgrade); 5. non-writable folder → actionable error, installed app unchanged;
6. a signed DMG whose version differs from the announced one → refused. The app's settings domain was hashed before and after: unchanged (the updater never touches settings or Application Support).
Rollback of a failed swap and the rejection of unsigned/wrong-identity DMGs are covered by `UpdateTests` (fixture apps).

**Limits (stated, not hidden).**
- The harness replaces only the network layer (manifest and DMG are served locally); the verification and installation code is the shipped code. The real GitHub download is exercised by the live check after publication.
- The app was not launched/clicked in this proof; the GUI path (sheet, progress, relaunch) is covered by build + wiring, not by an interactive run of a signed older build. The relaunch script is not executed by the harness.
- Gatekeeper is disabled on the build Mac (`spctl` reports only the origin), so "accepted by Gatekeeper" was not tested with Gatekeeper active.
- 0.5.1 has no updater: moving to 0.6.0 is a one-time manual download.
