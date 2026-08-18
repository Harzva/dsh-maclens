# AGENTS.md — for AI agents

This file is written for AI agents (Codex, dsh, Claude Code, …) that may be
asked to install, use, or extend dsh-maclens. Read this instead of the full
README when you need to act.

## What this is

`dsh-maclens` is a DeepSeek Harness plugin exposing Apple's on-device Vision
framework as local tools. It is a **CV toolkit** (OCR / classify / detect),
**not** a vision-language model — it never narrates image semantics.

## Install

```sh
# From npm (prebuilt binary included — no build step):
dsh plugin --profile desktop add dsh-maclens

# From a checkout:
cd dsh-maclens && bash scripts/build.sh && dsh plugin --profile desktop add ./dsh-maclens
```

Binary resolution: package `bin/maclens` → `$MACLENS_BIN` → `swift/.build/release/MaclensBridge` → `maclens` on PATH. The plugin auto-`chmod`s the binary to 0755 (npm tarballs drop the exec bit).

## Tools

| Tool | Purpose | Extra args |
|---|---|---|
| `maclens_ocr(path)` | All visible text + confidence + normalized bbox | `languages`, `maxLines`, `slice`, `sliceHeight` |
| `maclens_classify(path)` | Top-N categories | `top` |
| `maclens_faces(path)` | Face boxes + count | — |
| `maclens_document(path)` | OCR + column layout | `languages`, `maxLines`, `slice`, `sliceHeight` |
| `maclens_describe(path)` | OCR + classify + faces + layout | `languages`, `top`, `maxLines`, `slice`, `sliceHeight` |

## Calling rules

- `path` is **required** on every tool and must be an **absolute** local path.
- OCR-family `slice: true` when the image is taller than ~4000px (chat logs, scrolling screenshots).
- `bbox` is normalized 0–1, origin top-left.
- Result is JSON: `{"task": ..., "lines": [...], ...}`. Failure: `{"error": "..."}`.
- **Never fabricate OCR output** — if the tool errors, report the error.

## Extending

- Swift CLI: `swift/Sources/MaclensBridge/main.swift` (Vision requests per task).
- Tools registered in `lib/index.js` (`ctx.tools.register`).
- Rebuild binary after Swift changes: `bash scripts/build.sh`.
- Tests: `swift test --package-path swift`. CI runs them on push.
- npm release: bump `version` in `package.json` + `CHANGELOG.md`, then `pnpm publish`.
