# Signed and Notarized Releases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The release workflow signs Ajour with the owner's Developer ID, notarizes and staples it, and only attaches a zip Gatekeeper accepts.

**Architecture:** The existing composite build action gains an optional team ID that switches the Release build to Developer ID signing. Two new composite actions do the rest: one installs the certificate into a temporary keychain, one verifies, notarizes, staples, checks and re-zips the app. The release workflow wires them together and gains a manual trigger that runs the same path on a branch and uploads the zip as an artifact.

**Tech Stack:** GitHub Actions composite actions (bash), `security`, `codesign`, `xcrun notarytool`, `xcrun stapler`, `spctl`, `ditto`.

**Spec:** `docs/superpowers/specs/2026-11-04-release-signing-design.md`

## Global Constraints

- Team ID `KA74RG7337`, committed in the release workflow, not a secret.
- Secrets: `DEVELOPER_ID_CERTIFICATE`, `DEVELOPER_ID_CERTIFICATE_PASSWORD`, `NOTARY_API_KEY`, `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER_ID`. Only the release workflow reads them.
- CI tests and the `build` label build stay ad-hoc signed.
- No secret value is echoed; decoded key files live in `$RUNNER_TEMP` and are deleted even when the job fails.
- `actionlint` passes on every workflow.

## Review Focus

- A wrong certificate password: the import step fails with a clear error, not a later `codesign` "no identity found".
- Apple rejects the submission: the run prints the notary log and fails before anything is attached.
- A rerun of a tag's release: the stapled zip replaces the asset on the existing draft.
- A failed run: the temporary keychain and key files are gone afterwards.
- A manual run on a branch: it never creates or touches a release.

---

### Task 1: Signing, notarization and the manual trigger

**Files:**
- Modify: `.github/actions/build/action.yml`
- Create: `.github/actions/install-certificate/action.yml`
- Create: `.github/actions/notarize/action.yml`
- Modify: `.github/workflows/release.yml`

**Interfaces:**
- Build action: new input `team-id` (default empty). When set, adds `CODE_SIGN_IDENTITY="Developer ID Application"`, `DEVELOPMENT_TEAM=<team-id>`, `OTHER_CODE_SIGN_FLAGS=--timestamp`. New output `app`: path of the built `Ajour.app`.
- Install-certificate action: inputs `certificate` (base64 `.p12`), `password`. Creates `$RUNNER_TEMP/signing.keychain-db` with a random masked password, imports the identity and Apple's `DeveloperIDG2CA.cer`, sets the key partition list, adds the keychain to the user search list, and fails unless `security find-identity -v -p codesigning` finds exactly one Developer ID Application identity.
- Notarize action: inputs `app`, `archive`, `team-id`, `api-key` (base64 `.p8`), `api-key-id`, `api-issuer-id`. Verifies the signature (strict, team ID, timestamp), submits `archive` with `--wait`, prints the log and fails unless the status is `Accepted`, staples and validates, requires `spctl` to report `Notarized Developer ID`, and replaces `archive` with a zip of the stapled app.
- Release workflow: triggers `push` tags `v*` and `workflow_dispatch`. Tag check, release attach run only when `github.ref_type == 'tag'`; otherwise the zip is uploaded as an artifact named after the run. A final `if: always()` step deletes the keychain.

- [ ] **Step 1:** Implement the four files.
- [ ] **Step 2:** `actionlint` passes.
- [ ] **Step 3:** Commit.

### Task 2: Docs

**Files:**
- Modify: `README.md` (Install)
- Modify: `docs/mvp-manual-checks.md` (new `## Signed release`)

- [ ] **Step 1:** README: drop the Open Anyway step; replace the per-update Keychain note with a one-time note for people updating from 0.3.0 or earlier.
- [ ] **Step 2:** Manual checks: the downloaded zip opens without a Gatekeeper prompt; `spctl -a -vv /Applications/Ajour.app` names the Developer ID and `Notarized Developer ID`; updating from 0.3.0 asks for the Keychain once, keeps the key, the pins and the running timers, and doesn't ask to access another app's data.
- [ ] **Step 3:** Commit.

### Task 3: Verify on the branch

- [ ] **Step 1:** Push the branch and run the release workflow manually on it (`gh workflow run release.yml --ref release-signing`). If GitHub refuses because `main` has no manual trigger yet, add a temporary `push` trigger for the branch in a separate commit, and drop that commit before the PR.
- [ ] **Step 2:** The run is green. Download the artifact into a new empty directory and check it with `codesign -dvv`, `xcrun stapler validate` and `spctl -a -vv -t execute`, without launching the app.
- [ ] **Step 3:** Open the PR; comment on #36.
