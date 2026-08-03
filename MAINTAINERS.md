# Maintainers

## Current maintainer

- **Yalamber Ingnam** ([@YalamberIngnam](https://github.com/YalamberIngnam)) — founder, initial maintainer, and release owner.

Security reports must use [GitHub private vulnerability reporting](https://github.com/YalamberIngnam/appsleuth/security/advisories/new). General questions and reproducible bugs belong in repository issues after checking the support guide. The maintainer's Git commit email is not the public security channel.

## Responsibilities

Maintainers are responsible for:

- protecting the safety invariants in `docs/SAFETY.md`;
- triaging issues and private vulnerability reports;
- reviewing or assigning review for pull requests;
- keeping CI, supported macOS versions, documentation, and release tooling current;
- publishing signed, checksummed releases and updating the Homebrew tap;
- documenting conflicts of interest and recusing when appropriate;
- arranging succession or clearly marking the project unmaintained.

No maintainer should merge their own safety-critical matching, restore, confirmation, or privileged-operation change without an independent review once the project has more than one active maintainer.
