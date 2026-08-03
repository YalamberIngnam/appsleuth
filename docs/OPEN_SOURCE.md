# Open-source project operations

## Hosting on GitHub

Create an empty public GitHub repository named `appsleuth`, without generating replacement README or license files. Then connect this local repository:

```bash
git add .
git commit -m "Initial AppSleuth MVP"
git remote add origin https://github.com/YOUR-USERNAME/appsleuth.git
git push -u origin main
```

If GitHub CLI is installed and authenticated, the creation and push can be combined after the initial commit:

```bash
gh repo create appsleuth --public --source=. --remote=origin --push
```

Choose the owner account or organization deliberately; that choice determines the final clone URL, security-contact URL, and Homebrew tap name used throughout the documentation.

The repository owner should enable:

- Issues and private vulnerability reporting;
- branch protection or a ruleset for `main`;
- required passing `Apple Silicon build and test` status;
- pull requests for non-trivial changes;
- resolved review conversations before merging;
- tag/release protection when the release process stabilizes.

For a solo-maintained beta, require pull requests, passing CI, resolved conversations, and blocked force-push/deletion on `main`, but do not require a second approving reviewer until another trusted maintainer exists. Otherwise routine maintenance can become impossible. Turn on immutable releases and private vulnerability reporting as soon as the public repository exists.

Do not put signing certificates, API keys, tokens, personal paths, real scan reports, or backup manifests in the repository.

## Files every contributor should find quickly

| File | Purpose |
|---|---|
| `README.md` | Product promise, installation, examples, limitations |
| `LICENSE` | Legal permission to use and contribute (MIT) |
| `CONTRIBUTING.md` | Development and review expectations |
| `CODE_OF_CONDUCT.md` | Community behavior |
| `SECURITY.md` | Private vulnerability reporting and supported versions |
| `MAINTAINERS.md` | Ownership, triage, releases, and succession |
| `CHANGELOG.md` | User-visible changes by version |
| `docs/SAFETY.md` | Non-negotiable deletion and restore invariants |

## Maintenance model

Use a lightweight GitHub-flow process:

1. Open or confirm an issue for meaningful behavior changes.
2. Work on a short-lived branch such as `feature/progress-output` or `fix/scan-timeout`.
3. Open a pull request against `main`.
4. Require tests for every matching, path, restore, privilege, or confirmation change.
5. Merge only with green CI and resolved review feedback.
6. Release from a reviewed commit on `main` using semantic version tags.

Suggested labels:

- `bug`, `enhancement`, `documentation`;
- `safety-critical`, `matching-rule`, `vendor-recipe`;
- `good first issue`, `help wanted`;
- `needs-reproduction`, `blocked`, `release`.

## Triage and support cadence

- Acknowledge safety/data-loss reports as soon as possible and move details to private security reporting.
- Triage ordinary issues weekly while the project is active.
- Keep the roadmap honest; close unsupported feature requests with a reason.
- Review dependency/toolchain and supported-macOS changes monthly or before a release.
- Publish security fixes promptly and disclose them through GitHub Security Advisories.
- If maintenance stops, say so in the README and archive the repository rather than leaving users uncertain.

## Versioning

Use semantic versions:

- patch (`0.1.1`): compatible fixes and safety hardening;
- minor (`0.2.0`): new commands or compatible capabilities;
- major (`1.0.0`): a stable contract; afterward, breaking CLI/manifest changes require a major version.

Before `1.0`, clearly call out breaking changes even when semantic versioning permits them in a minor release. Backup manifest migrations need explicit compatibility tests.

The first public build is `0.1.0-beta.1`, not stable `0.1.0`. This communicates that destructive paths have local regression coverage but still need independent review and feedback across real Macs. A stable label should describe evidence, not optimism.
