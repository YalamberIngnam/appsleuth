# Distribution and installation

## Installation stages

AppSleuth uses a staged distribution plan so that convenience does not outrun release security.

### 1. Local source install — available now

```bash
git clone https://github.com/YalamberIngnam/appsleuth.git
cd appsleuth
./scripts/install.sh
appsleuth
```

The installer builds a release binary and chooses the first suitable location:

1. `$PREFIX/bin` when `PREFIX` is supplied;
2. `/opt/homebrew/bin` on an Apple Silicon Homebrew setup when writable;
3. `/usr/local/bin` when writable;
4. `~/.local/bin` as a no-administrator fallback.

If the chosen location is not already in `PATH`, the installer prints the exact `.zprofile` line to add. It does not edit shell configuration automatically.

The source installer installs the canonical `appsleuth` executable and, when the name is available, an `appsl` symbolic-link command alias. It refuses to overwrite an unrelated existing `appsl` command and removes only the retired `aps` symlink previously owned by AppSleuth.

Equivalent Make targets are available:

```bash
make install
make test
make uninstall
```

`make uninstall` removes the executable and its AppSleuth-owned command symlinks. Restore vaults remain untouched so users do not lose recovery data.

### 2. GitHub Releases — workflow ready

The release workflow runs when a semantic version tag such as `v0.1.0-beta.1` is pushed. It:

- tests on an Apple Silicon GitHub runner;
- builds an optimized ARM64 executable;
- applies an ad-hoc signature;
- creates a compressed release asset and SHA-256 checksums;
- creates a GitHub artifact attestation that links the archive to its source and build workflow;
- publishes a GitHub Release with generated notes.

Tags containing a prerelease suffix, such as `-beta.1`, are automatically marked as prereleases on GitHub.

Ad-hoc signing is not Apple notarization. Before recommending direct binary downloads to non-developers, obtain a Developer ID certificate, sign with it, notarize the artifact, staple where applicable, and document verification.

### 3. Personal Homebrew tap — next after the first release

Create a separate public repository named `homebrew-tap` under the same GitHub account. Homebrew recognizes that naming convention:

```bash
brew tap-new YalamberIngnam/homebrew-tap
```

After publishing a stable `v0.1.0`, add `Formula/appsleuth.rb` to that tap. Do not point the default Homebrew formula at a beta unless the formula is explicitly named and documented as a prerelease:

```ruby
class Appsleuth < Formula
  desc "Evidence-first macOS application uninstaller"
  homepage "https://github.com/YalamberIngnam/appsleuth"
  url "https://github.com/YalamberIngnam/appsleuth/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_RELEASE_ARCHIVE_SHA256"
  license "MIT"

  depends_on macos: :ventura
  depends_on xcode: ["15.0", :build]

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/appsleuth"
    bin.install_symlink "appsleuth" => "appsl"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/appsleuth version")
  end
end
```

Test it before publishing:

```bash
brew install --build-from-source YalamberIngnam/tap/appsleuth
brew test YalamberIngnam/tap/appsleuth
brew audit --strict YalamberIngnam/tap/appsleuth
```

Users can then install with:

```bash
brew install YalamberIngnam/tap/appsleuth
appsleuth
```

Use the fully qualified formula name until the tap trust/short-name behavior is deliberately configured.

### 4. `brew install appsleuth` — long-term

The unqualified command normally means acceptance into `homebrew/core` or a trusted/tapped source. Core requires a stable tagged release, an open-source license, immutable and checksummed sources, reproducible builds, passing audits/tests, and support for its current CI platforms. A personal tap is the practical first distribution route; apply to core after the project has real users and a stable maintenance record.

## Release checklist

Use the complete [release process](RELEASING.md). It covers prerelease labeling, immutable action references, checksums, provenance verification, signing/notarization limits, and Homebrew updates.
