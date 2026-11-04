# Ajour: Signed and Notarized Releases

Status: draft for review
Date: 2026-11-04
Builds on: the release workflow in `.github/workflows/release.yml`, issue #36

## Intent

People who download a release open Ajour like any other app. macOS doesn't block the first launch, and it doesn't ask again for the Keychain after every update. The release workflow signs with the owner's Developer ID, has Apple notarize the app, and refuses to publish a build Gatekeeper would reject.

## Non-goals

- Signing debug builds, test runs, or the app the `build` label makes for a pull request. They stay ad-hoc signed and don't need the secrets.
- A `.pkg` installer, a DMG, or a built-in updater.
- Submitting to `homebrew/cask` (#36 still needs notability).

## Anti-goals

- A release that is signed but not notarized, or notarized but not stapled. Any failed step fails the run, and no zip is attached.
- Secrets in logs, in the repository, or available to workflows that run for pull requests.
- Stripping the quarantine attribute anywhere.

## What the owner has set up

- A Developer ID Application certificate for team `KA74RG7337`, exported as `.p12`.
- An App Store Connect API key with the Developer role for `notarytool`.
- Repository secrets:
  - `DEVELOPER_ID_CERTIFICATE`: the `.p12`, base64;
  - `DEVELOPER_ID_CERTIFICATE_PASSWORD`;
  - `NOTARY_API_KEY`: the `.p8`, base64;
  - `NOTARY_API_KEY_ID`;
  - `NOTARY_API_ISSUER_ID`.

## 1. Signing in the release build

- The team ID is public (it is part of every signed app), so it lives in the repository, not in a secret.
- `project.yml` keeps ad-hoc signing as the default, so local builds and CI tests need no certificate.
- The build action gets an optional signing input. When it is set, `xcodebuild` builds the Release configuration with:
  - `CODE_SIGN_IDENTITY="Developer ID Application"`;
  - `DEVELOPMENT_TEAM=KA74RG7337`;
  - `OTHER_CODE_SIGN_FLAGS=--timestamp`.
  Hardened Runtime is already on. The Release build must not carry `com.apple.security.get-task-allow`, which notarization rejects.
- Only the release workflow sets the input.

## 2. Certificate on the runner

- A step imports the `.p12` into a temporary keychain with a random password, allows `codesign` to use the key without a prompt, and puts the keychain first in the search list.
- It also installs Apple's `Developer ID - G2` intermediate certificate, so the chain is complete whatever the runner image ships.
- A final step that runs even when the job fails deletes the keychain and the key files.

## 3. Notarize, staple, check

After the build, in this order:

1. `codesign --verify --strict --deep` passes, and the signature names team `KA74RG7337` with a secure timestamp.
2. The app is zipped with `ditto` and sent with `xcrun notarytool submit --wait` using the API key. When Apple rejects it, the step prints `notarytool log` for that submission and fails.
3. `xcrun stapler staple` attaches the ticket to `Ajour.app`.
4. `spctl --assess --type execute` accepts the app, and `stapler validate` passes.
5. The stapled app is zipped again with `ditto -c -k --keepParent`. This zip is what the draft release gets.

The release stays a draft; publishing remains manual.

## 4. Keychain and sandbox container after the switch

- Today every ad-hoc build has its own identity, so macOS asks for the Keychain after each update. With Developer ID the item's access follows the team and bundle ID, so it asks one last time on the first signed version and then not again.
- The sandbox container belongs to the app's signer. The first signed version must still read the existing container (timer data, pins) without asking to access another app's data. The builder checks both on the owner's Mac only if the owner asks; otherwise they go into the manual checks.

## 5. Docs

- README "Install": drop the "Open Anyway" step. Replace the note about the Keychain prompt after every update with a one-time note for people updating from 0.3.0 or earlier.
- `docs/mvp-manual-checks.md`: a short "Signed release" section: the downloaded zip opens without a Gatekeeper prompt, `spctl -a -vv` names the Developer ID, and the update from an ad-hoc build keeps the key and the timers.
- Issue #36: a comment that releases are now signed and notarized.

## Verification the builder can do

- A test tag on the branch would be rejected, because release tags must be on main. Instead, the workflow gets a `workflow_dispatch` trigger. It runs the whole signing and notarization path on any ref and uploads the zip as a workflow artifact instead of a release.
- The builder runs it on the branch before the PR is merged, downloads the artifact, and checks it locally with `spctl`, `codesign -dv` and `stapler validate`. That only reads the downloaded app; it doesn't launch it.

## Constraints

- Swift 6, macOS 26, Xcode 27.1, XcodeGen. Runner label `xcode-27`.
- No secrets in the repository, logs, or pull-request workflows.
- Merge to main only via PR with a green `test` check and the owner's approval.
