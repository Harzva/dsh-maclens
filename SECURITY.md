# Security

dsh-maclens is designed to be a minimal local bridge with no external attack surface:

- **No network**: the Swift CLI and the plugin make zero network requests. There is no telemetry, no update check, no remote resource loading.
- **No daemon, no ports**: the plugin spawns the Swift binary per call and tears it down. Nothing listens on any socket.
- **No credentials**: there is no API key, token, or secret anywhere in the codebase, config, or runtime.
- **Read-only image access**: the tools read the image file you point them at and return text/JSON. They never modify the image or write outside the plugin's own directory.
- **Apple Vision runs on-device**: images are processed by the OS Vision framework locally (Neural Engine / CPU). Nothing leaves your machine.

## What a malicious agent could still do

A dsh agent that calls `maclens_*` tools can read any image file it has path access to (the tools accept an arbitrary absolute path). That is the same access the agent already has through dsh's file tools — maclens adds no new capability. As with any agent tool, follow the [awesome-dsh-plugin warning](https://github.com/awesome-dsh-plugin/awesome-dsh-plugin): check the source before installing, and avoid running it somewhere that holds keys you care about.

## Reporting a vulnerability

Open an issue on [github.com/Harzva/dsh-maclens](https://github.com/Harzva/dsh-maclens/issues) — or, for anything sensitive, reach out privately via the issue tracker's contact options.
