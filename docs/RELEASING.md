# Release process

AppSleuth releases are safety events, not only packaging events. A release is made from a reviewed commit on `main`; local working-tree archives are not release artifacts.

## Version policy

- Use `0.1.0-beta.N` while destructive workflows still need independent real-world review.
- A beta tag must create a GitHub prerelease, not a stable release.
- Patch versions contain compatible fixes and safety hardening.
- Minor versions add compatible commands or capabilities.
- Before `1.0.0`, document every breaking CLI or backup-manifest change even when semantic versioning would permit it.

The executable version and tag must match exactly: version `0.1.0-beta.1` uses tag `v0.1.0-beta.1`.

## Before tagging

1. Confirm the intended release commit is on `main`, the worktree is clean, and required CI is green.
2. Review every matching, path-policy, confirmation, privilege, restore, permanent-deletion, and maintenance-action change separately from unrelated refactoring.
3. Move the release notes from `Unreleased` into a dated version section in `CHANGELOG.md`.
4. Confirm version strings, supported macOS versions, known limitations, and upgrade notes.
5. Run:

   ```bash
   swift package dump-package > /dev/null
   swift test --parallel
   swift build -c release
   .build/release/appsleuth version
   ```

6. Exercise read-only smoke tests on a clean macOS user account. Do not use a personally important app for a mutation test.
7. Confirm workflow actions are pinned to full commit SHAs and review any Dependabot action update before merging it.

## Tag and automated build

Prefer a cryptographically signed tag when Git signing is configured:

```bash
git tag -s v0.1.0-beta.1 -m "AppSleuth 0.1.0-beta.1"
git push origin v0.1.0-beta.1
```

An annotated tag is acceptable only while signing is not configured; disclose that limitation. Never move or reuse a published release tag.

The release workflow tests the tagged source, builds on Apple Silicon, checks that the executable version equals the tag, applies an ad-hoc code signature, creates the archive and `SHA256SUMS`, generates a GitHub artifact attestation, and publishes the release. A tag with a hyphenated suffix is marked as a prerelease.

Ad-hoc signing is not Developer ID signing or Apple notarization. Do not describe the binary as notarized until the workflow actually performs and verifies those steps.

## Verify before announcing

1. Download the archive and `SHA256SUMS` from the GitHub Release on a clean Mac.
2. Verify the checksum:

   ```bash
   shasum -a 256 -c SHA256SUMS
   ```

3. Verify build provenance after replacing the repository owner:

   ```bash
   gh attestation verify appsleuth-v0.1.0-beta.1-macos-arm64.tar.gz -R YalamberIngnam/appsleuth
   ```

4. Extract the archive, confirm the architecture with `file`, run `appsleuth version`, and exercise help plus read-only `doctor`, `list`, and fixture scans.
5. Confirm the release is labeled prerelease when appropriate and that generated notes do not expose usernames, private paths, scan reports, backup IDs, or secrets.
6. Record known limitations. If verification fails, remove the bad release asset or release, fix the source, and issue a new version; do not silently replace an immutable artifact under the same tag.

## Homebrew

Update a Homebrew tap only after the GitHub release is immutable and verified. The formula URL must name the exact tag, and its SHA-256 must match the published source or binary archive. Test installation, the formula test, and a strict audit before advertising the tap. Keep beta formulas explicitly identified as prereleases; do not make them the default stable installation path.
