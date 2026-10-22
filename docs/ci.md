# Continuous integration and releases

GitHub Actions runs on the `xcode-27` runner image with Xcode 27.1, the version the app is developed with.

- **Pushes to `main` and pull requests:** run the SimpleLoginKit and app tests.
- **Builds for pull requests:** add the `build` label to a pull request. The workflow removes the label, builds the app, and comments with a download link. The build is kept for 14 days. To build a newer commit, add the label again.
- **Releases:** push a tag like `v1.2.3` that points to a commit on `main`. The release workflow tests, builds the app with version 1.2.3, and attaches `Ajour-1.2.3.zip` to a draft release with generated notes. Review the draft on GitHub and publish it.

```sh
git tag v1.2.3 && git push origin v1.2.3
```

Builds are ad-hoc signed, because signing for distribution needs a paid Apple Developer account. macOS therefore asks before opening a downloaded build the first time: open it once, then allow it in System Settings > Privacy & Security.
