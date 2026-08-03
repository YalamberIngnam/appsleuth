# Why Swift, and could AppSleuth use Python?

## Short answer

Yes, AppSleuth could be written in Python. Swift was chosen because this project is macOS-only, safety-sensitive, and intended to install as one native command without asking users to manage a Python environment.

## Tradeoffs

| Concern | Swift | Python |
|---|---|---|
| macOS bundle/plist APIs | Native Foundation support | Standard-library plist support; deeper APIs often need PyObjC |
| User installation | One compiled executable | Requires a managed Python runtime, `pipx`, Homebrew Python, or a bundled executable |
| Startup and memory | Fast native startup, compact runtime behavior | Usually slower startup; bundled applications are larger |
| Contributor learning curve | Higher outside Apple development | Lower and excellent for rapid prototyping |
| Terminal UI ecosystem | Manual ANSI/termios or a Swift package | Rich mature options such as Rich/Textual |
| Native macOS evolution | Direct path to ServiceManagement and code-signing APIs | Possible, but bridging and packaging add complexity |
| Cross-platform potential | Possible but this code is intentionally macOS-specific | Strong, if the product scope later expands |

## Recommendation

Keep the safety core and CLI in Swift through the first stable release. Rewriting now would reset tested path, matching, transaction, and restore behavior without improving the core product promise. Python becomes the better choice if the project changes direction toward cross-platform cleanup, prioritizes rapid plugin scripting over a single native binary, or cannot attract Swift contributors.

Do not maintain separate Swift and Python implementations of deletion policy. Two safety engines will drift. If Python extensibility is added later, use declarative, validated recipes or an IPC boundary while the Swift core remains the only component allowed to move files.
