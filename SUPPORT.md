# Support

AppSleuth is a volunteer-maintained prerelease project. Help is best-effort, and a response time is not guaranteed.

## Before asking for help

1. Read the [README](README.md) and [troubleshooting guide](docs/TROUBLESHOOTING.md).
2. Run `appsleuth version` and the read-only `appsleuth doctor` command.
3. Reproduce the problem with a dry-run or read-only command whenever possible.
4. Remove usernames, private paths, bundle data, backup IDs, tokens, and other secrets from terminal output.

Use a [GitHub issue](https://github.com/YalamberIngnam/appsleuth/issues) for reproducible bugs and scoped feature requests. Include the AppSleuth version, macOS version, Apple Silicon model, exact sanitized steps, expected behavior, and actual behavior.

Do not open a public support issue for unintended data movement, a policy bypass, or another possible vulnerability. Follow [SECURITY.md](SECURITY.md) and use GitHub private vulnerability reporting.

AppSleuth cannot provide emergency data recovery. Stop executing cleanup commands if important data may have moved, preserve the restore vault, and avoid making unrelated filesystem changes until the situation is understood.
