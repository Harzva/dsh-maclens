# dsh-maclens 🍎🔍

> Apple's **on-device Vision framework**, bridged into [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (`dsh`) as local tools: OCR, image classification, face detection, document layout, and a combined read — **100% offline, no API key, no daemon**.

| | |
|---|---|
| 🔒 **Privacy** | Every pixel stays on your Mac. No network, no upload, no telemetry. |
| ⚡ **Speed** | Sub-second OCR on typical screenshots (Neural Engine). |
| 🇨🇳 **Languages** | zh-Hans + 30+ recognition languages out of the box. |
| 🖼️ **Tall images** | `slice` splits long screenshots so small text survives Vision's downscale. |
| 🧩 **No deps** | Swift CLI ships in the npm package — no build step to install. |

---

## 👤 For humans — quick start (30 seconds)

```sh
# 1. Install into your dsh profile
dsh plugin --profile desktop add dsh-maclens

# 2. Restart DSH. Then just ask the model:
#    "OCR this screenshot: /Users/me/Desktop/shot.png"
```

**The five tools the model can call:**

| Tool | One-liner |
|---|---|
| `maclens_ocr` | "Read all the text in this image" — every line + confidence + box |
| `maclens_classify` | "What kind of image is this?" — document, chart, photo, … |
| `maclens_faces` | "Are there people in this image?" — face boxes + count |
| `maclens_document` | "Parse this page" — OCR + left/right column layout |
| `maclens_describe` | "Give me everything at once" — OCR + classify + faces + layout |

**When to pick maclens vs a VLM:** maclens is a CV toolkit — it *transcribes, classifies, detects* but does **not** narrate "what this image is about". Need open-ended understanding? Pair it with a VLM bridge (e.g. modlens + qwen-vl). Need fast, free, private OCR/detection? maclens.

---

## 🤖 For agents — precise contract

### TL;DR

```text
Plugin:     dsh-maclens (npm), installs with dsh plugin add
Runtime:    macOS 14+ with Xcode Command Line Tools (Swift 6+)
Tools:      maclens_ocr | maclens_classify | maclens_faces | maclens_document | maclens_describe
Input:      absolute local image path (string) — required on every tool
Output:     one JSON object on stdout; {"error": "..."} + exit 1 on failure
Binary:     bin/maclens in the package (auto-chmod'd), else MACLENS_BIN, else PATH
No network: the CLI makes zero network requests
```

### Install (exact commands)

```sh
# From npm — includes the prebuilt binary, no build step:
dsh plugin --profile desktop add dsh-maclens

# From a git checkout — build the Swift bridge first:
cd dsh-maclens && bash scripts/build.sh        # produces bin/maclens
dsh plugin --profile desktop add ./dsh-maclens
```

Binary resolution order: `bin/maclens` in the package → `$MACLENS_BIN` → `swift/.build/release/MaclensBridge` → `maclens` on PATH. The plugin `chmod`s the found binary to `0755` at resolve time (npm tarballs drop the exec bit).

### Tool schemas

All five tools take `path` (required, string). OCR-family tools additionally accept:

| Field | Type | Default | Meaning |
|---|---|---|---|
| `languages` | string | `zh-Hans,en-US` | Comma-separated recognition languages |
| `maxLines` | number | — | Cap returned OCR lines (large screenshots) |
| `slice` | boolean | false | Slice tall images into overlapping strips |
| `sliceHeight` | number | 4096 | Strip height in px when slicing |
| `top` | number | 5 | Classify only: how many categories to return |

### Output contract

`maclens_ocr` returns:

```json
{
  "task": "ocr",
  "language": ["zh-Hans", "en-US"],
  "full_text": "跨境增长研究室\n从一个问题，抵达一个决定。",
  "lines": [
    {
      "text": "跨境增长研究室",
      "confidence": 1.0,
      "bbox": { "x": 0.055, "y": 0.519, "width": 0.517, "height": 0.144 }
    }
  ],
  "line_count": 2,
  "truncated": false,
  "sliced": false
}
```

- `bbox` is **normalized** (0–1), origin **top-left** (converted from Vision's bottom-left so it is intuitive).
- With `slice: true`, tall images are split into overlapping strips, each strip OCR'd, results stitched back to whole-image coordinates, and duplicate lines in the overlap band de-duplicated. Output adds `"sliced": true` and `"slice_count": N`.
- `maclens_document` = `ocr` + `layout.columns` (left/right) + `layout.image_dimensions`.
- `maclens_describe` = `ocr` + `classification.observations` + `faces` + `layout`.
- `maclens_faces` → `faces[]` + `face_count`; `maclens_classify` → `observations[]` (`identifier`, `confidence`).

### Error contract

| Exit | Meaning |
|---|---|
| 0 | Success |
| 1 | Runtime error — stdout is `{"error": "..."}` (e.g. `file does not exist: <path>`) |
| 2 | Usage / unknown task — stdout is `{"error": "usage: ..."}` |

### Raw CLI (for testing outside dsh)

```sh
bin/maclens ocr --image /path/to/img.png
bin/maclens classify --image /path/to/img.png --top 3
bin/maclens faces --image /path/to/img.png
bin/maclens document --image /path/to/img.png --slice
bin/maclens describe --image /path/to/img.png --slice --top 2
```

---

## 🏗️ How it works

```
dsh (text-only model)
  └─ maclens_* tools (lib/index.js)
       └─ bin/maclens (Swift CLI, spawned per call — no daemon, no ports)
            └─ Apple Vision: VNRecognizeTextRequest / VNClassifyImageRequest /
               VNDetectFaceRectanglesRequest        ← on-device, offline
```

## 🧪 Development

```sh
cd swift && swift build -c release
swift test --package-path swift      # 6 behavioral tests
```

CI (GitHub Actions): Swift release build + smoke tests on macOS, plugin-load + pack-contents check on Ubuntu. All green on `main`.

## 📄 Docs

- [`AGENTS.md`](AGENTS.md) — the agent-facing quick reference (mirrors this section).
- [`CHANGELOG.md`](CHANGELOG.md) — version history.
- [`SECURITY.md`](SECURITY.md) — security model & reporting.

## License

MIT — see [LICENSE](LICENSE).
