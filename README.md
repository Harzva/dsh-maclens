# dsh-maclens

Bridge Apple's **on-device Vision framework** (macOS) into [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (`dsh`) as local tools: OCR, image classification, face detection, and document layout.

- 🔒 **100% local** — no network, no API key, no daemon, no upload. The Vision framework is already on your Mac.
- ⚡ **Fast** — sub-second OCR for typical screenshots, running on the Neural Engine.
- 🇨🇳 **Great Chinese OCR** — Vision's recognition supports zh-Hans + 30+ languages out of the box.
- 🖼️ **Tall-screenshot slicing** — `--slice` splits very tall images (chat logs, scrolling captures) into overlapping strips so small text is not lost to Vision's downscale.

## Tools

| Tool | What it does |
|---|---|
| `maclens_ocr` | Transcribe all visible text with confidence + bounding boxes |
| `maclens_classify` | Top-N category identifiers (document, chart, diagram, photo, …) |
| `maclens_faces` | Face bounding boxes and confidence |
| `maclens_document` | OCR + simple left/right column layout analysis |
| `maclens_describe` | One call combining OCR, classification, faces and layout |

## Install

Prerequisites: macOS (Vision framework), Xcode Command Line Tools (Swift 6+).

```sh
# 1. install from npm (bin/maclens ships in the package — no build needed)
dsh plugin --profile desktop add dsh-maclens

# 2. or, from a checkout: build the Swift bridge yourself
cd dsh-maclens
bash scripts/build.sh          # → bin/maclens
dsh plugin --profile desktop add ./dsh-maclens
```

The plugin spawns `bin/maclens` (or `swift/.build/release/MaclensBridge`, or a `maclens` on PATH — set `MACLENS_BIN` to pin a specific binary).

## Usage

Each tool takes an absolute image path. All OCR-based tools accept:

| Argument | Meaning |
|---|---|
| `languages` | Comma-separated recognition languages (default `zh-Hans,en-US`) |
| `maxLines` | Cap OCR output (large screenshots) |
| `slice` | Slice tall images into overlapping strips for reliable OCR |
| `sliceHeight` | Strip height in pixels when slicing (default 4096) |

`maclens_describe` additionally accepts `top` (number of classification categories).

## How it works

```
dsh (text-only model)
  └─ maclens_ocr / classify / faces / document / describe   ← dsh tools (lib/index.js)
       └─ bin/maclens (Swift CLI)                           ← swift/Sources/MaclensBridge
            └─ Apple Vision framework (VNRecognizeTextRequest, VNClassifyImageRequest,
               VNDetectFaceRectanglesRequest)               ← on-device, offline
```

> **Positioning note:** Vision is a computer-vision toolkit, not a vision-language model. `maclens_*` transcribes, classifies, and detects — it does not produce free-form semantic description ("what is this image about"). Pair it with a VLM bridge (e.g. modlens + qwen-vl) when you need open-ended understanding; use `maclens_*` when you want fast, free, private OCR and detection.

## Development

```sh
cd swift && swift build -c release
.build/release/MaclensBridge ocr --image /path/to/img.png
.build/release/MaclensBridge classify --image /path/to/img.png --top 3
.build/release/MaclensBridge describe --image /path/to/img.png --slice

# tests
swift test --package-path swift
```

## License

MIT
