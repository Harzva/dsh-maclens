# dsh-maclens

Bridge Apple's **on-device Vision framework** (macOS) into [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (`dsh`) as local tools: OCR, image classification, face detection, and document layout.

- 🔒 **100% local** — no network, no API key, no daemon, no upload. The Vision framework is already on your Mac.
- ⚡ **Fast** — sub-second OCR for typical screenshots, running on the Neural Engine.
- 🇨🇳 **Great Chinese OCR** — Vision's recognition supports zh-Hans + 30+ languages out of the box.

## Tools

| Tool | What it does |
|---|---|
| `maclens_ocr` | Transcribe all visible text with confidence + bounding boxes |
| `maclens_classify` | Top-N category identifiers (document, chart, diagram, photo, …) |
| `maclens_faces` | Face bounding boxes and confidence |
| `maclens_document` | OCR + simple left/right column layout analysis |

## Install

Prerequisites: macOS (Vision framework), Xcode Command Line Tools (Swift).

```sh
# 1. clone or copy this repo, then build the Swift bridge
cd dsh-maclens
bash scripts/build.sh          # → bin/maclens

# 2. install the plugin into a dsh profile
dsh plugin --profile desktop add ./dsh-maclens     # local path install
# or, once published: dsh plugin --profile desktop add dsh-maclens
```

The plugin spawns `bin/maclens` (or `swift/.build/release/MaclensBridge`, or a `maclens` on PATH — set `MACLENS_BIN` to pin a specific binary).

## How it works

```
dsh (text-only model)
  └─ maclens_ocr / classify / faces / document   ← dsh tools (lib/index.js)
       └─ bin/maclens (Swift CLI)                ← swift/Sources/MaclensBridge
            └─ Apple Vision framework (VNRecognizeTextRequest, VNClassifyImageRequest,
               VNDetectFaceRectanglesRequest)    ← on-device, offline
```

## Development

```sh
cd swift && swift build -c release
.build/release/MaclensBridge ocr --image /path/to/img.png
.build/release/MaclensBridge classify --image /path/to/img.png --top 3
```

## License

MIT
