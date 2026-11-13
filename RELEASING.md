# Releasing

Notes for maintainers. Releases are signed with a Developer ID, notarized by Apple, published as
GitHub releases and installed through the
[backbonesk/homebrew-tap](https://github.com/backbonesk/homebrew-tap) cask.

## One-time setup

`scripts/release.sh` takes all account-specific values from environment variables, so none are
committed:

| Variable           | Purpose                                                                       |
|--------------------|-------------------------------------------------------------------------------|
| `DEVELOPMENT_TEAM` | Apple Developer Team ID; without it the build is ad-hoc signed                |
| `SIGN_IDENTITY`    | Signing identity, default `Developer ID Application`                          |
| `NOTARY_PROFILE`   | `notarytool` keychain profile; when set, the app is notarized and stapled     |
| `GITHUB_REPO`      | `owner/repo` of the releases; when set, writes the cask to `build/ip-calc.rb` |

1. Install the Developer ID Application certificate in your keychain.
2. Store notarization credentials (needs an app-specific password for the Apple ID):
   ```sh
   xcrun notarytool store-credentials <profile> --apple-id <Apple ID> --team-id <team ID>
   ```
3. Copy `scripts/release.local.sh.example` to `scripts/release.local.sh` (git-ignored) and fill in
   your values.

If notarytool reports *"A required agreement is missing or has expired"*, the team's Account Holder
has to accept the updated agreement at developer.apple.com/account (and check App Store Connect →
Business). Other team members don't see the prompt.

## Release steps

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in `project.yml` and commit.
2. Run `scripts/release.local.sh`. It runs the tests, builds and signs the app, notarizes and staples
   it, and writes `build/IP-Calc-<version>.zip` and the filled-in cask `build/ip-calc.rb`.
3. Tag and publish the release with the zip attached:
   ```sh
   git tag v<version> && git push origin v<version>
   gh release create v<version> build/IP-Calc-<version>.zip --title "IP Calc <version>" --notes "…"
   ```
4. Copy `build/ip-calc.rb` to `Casks/ip-calc.rb` in the tap repository and push.
5. Check: `brew update && brew upgrade --cask ip-calc` (or `brew install --cask backbonesk/tap/ip-calc`).
