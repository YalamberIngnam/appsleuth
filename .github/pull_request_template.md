## Summary

Describe the user-visible change and why it is needed.

## Safety impact

- [ ] No matching, removal, restore, confirmation, privilege, or path-policy behavior changes
- [ ] Safety-sensitive behavior changed and has focused positive/negative regression tests
- [ ] Shared-vendor and unrelated-path behavior was considered

## Verification

- [ ] `swift test`
- [ ] `swift build -c release`
- [ ] Documentation and changelog updated where needed

## Screenshots or terminal output

Sanitize usernames, filesystem paths, bundle data, backup IDs, and secrets.
