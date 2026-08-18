# dsh-maclens

将苹果 **设备端 Vision 框架**（macOS）桥接进 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh`），提供本地工具：OCR 文字识别、图像分类、人脸检测与文档版面分析。

- 🔒 **100% 本地** — 无网络、无 API key、无常驻进程、无上传。Vision 框架就在你的 Mac 上。
- ⚡ **快** — 常见截图 OCR 亚秒级完成，跑在神经网络引擎上。
- 🇨🇳 **中文 OCR 出色** — 原生支持 zh-Hans 及 30+ 种语言。
- 🖼️ **长截图切片** — `--slice` 把超长图（聊天记录、滚动截图）切成重叠条带分别识别，避免 Vision 缩放导致小字丢失。

## 工具

| 工具 | 功能 |
|---|---|
| `maclens_ocr` | 提取全部可见文字，含置信度与边框 |
| `maclens_classify` | 图像分类 Top-N（文档、图表、示意图、照片等） |
| `maclens_faces` | 人脸检测，返回边框与置信度 |
| `maclens_document` | OCR + 简单左右双栏版面分析 |
| `maclens_describe` | 一次调用合并 OCR、分类、人脸与版面 |

## 安装

前置条件：macOS（Vision 框架）、Xcode Command Line Tools（Swift 6+）。

```sh
# 1. 从 npm 安装（包内自带编译好的 bin/maclens，无需构建）
dsh plugin --profile desktop add dsh-maclens

# 2. 或从源码构建 Swift 桥
cd dsh-maclens
bash scripts/build.sh          # → bin/maclens
dsh plugin --profile desktop add ./dsh-maclens
```

插件按顺序查找 `bin/maclens`、`swift/.build/release/MaclensBridge`、PATH 上的 `maclens`；可用环境变量 `MACLENS_BIN` 指定固定二进制。

## 参数

每个工具接受图片绝对路径。所有 OCR 系工具支持：

| 参数 | 含义 |
|---|---|
| `languages` | 识别语言（默认 `zh-Hans,en-US`） |
| `maxLines` | 限制 OCR 输出行数（超大截图） |
| `slice` | 长图切片识别 |
| `sliceHeight` | 切片条带高度（默认 4096） |

`maclens_describe` 额外支持 `top`（分类数量）。

## 工作原理

```
dsh（纯文本模型）
  └─ maclens_ocr / classify / faces / document / describe   ← dsh 工具（lib/index.js）
       └─ bin/maclens（Swift CLI）                          ← swift/Sources/MaclensBridge
            └─ Apple Vision 框架（VNRecognizeTextRequest 等）← 设备端、离线
```

> **定位说明**：Vision 是计算机视觉工具箱，不是视觉语言模型。`maclens_*` 负责转写、分类、检测，不做开放式语义描述（"这张图讲什么"）。需要开放理解时请配合 VLM 桥（如 modlens + qwen-vl）；需要快速、免费、私密的 OCR 与检测时用 `maclens_*`。

## 开发

```sh
cd swift && swift build -c release
.build/release/MaclensBridge ocr --image /path/to/img.png
.build/release/MaclensBridge describe --image /path/to/img.png --slice

# 测试
swift test --package-path swift
```

## 许可

MIT
