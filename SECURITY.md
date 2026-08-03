# Security policy

## Supported versions

The project is pre-1.0. Security fixes are applied to the latest release and the `main` branch.

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/YalamberIngnam/appsleuth/security/advisories/new). If it is temporarily unavailable, contact [@YalamberIngnam](https://github.com/YalamberIngnam) privately through the profile contact listed on GitHub. Do not include private filesystem paths or backup manifests in a public issue.

Especially important reports include:

- escaping an approved discovery root;
- symlink, hard-link, or time-of-check/time-of-use bypasses;
- unintended selection of shared or unrelated data;
- restore overwrites or path traversal;
- confirmation bypasses;
- manifest tampering that moves data outside a backup vault.

Please include the AppSleuth version, macOS version, architecture, exact non-destructive reproduction steps, and sanitized scan/plan JSON when possible.

## Safety note

Until a report is resolved, use only `scan`, `explain`, and dry-run plans. Do not publish a proof of concept that risks user data.
