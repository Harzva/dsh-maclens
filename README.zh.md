# dsh-maclens 🍎🔍

> 将苹果**设备端 Vision 框架**桥接进 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh`），提供本地工具：OCR 文字识别、图像分类、人脸检测、文档版面分析——**100% 离线，无需 API key，无常驻进程**。

| | |
|---|---|
| 🔒 **隐私** | 每个像素都留在你的 Mac 上。无网络、无上传、无遥测。 |
| ⚡ **速度** | 常见截图 OCR 亚秒级完成（神经网络引擎）。 |
| 🇨🇳 **语言** | 原生支持 zh-Hans 及 30+ 种识别语言。 |
| 🖼️ **长图** | `slice` 切片识别超长截图，小字不再丢失。 |
| 🧩 **零依赖** | Swift CLI 随 npm 包内置，安装无需构建。 |

---

## 👤 人类读者 — 30 秒上手

```sh
# 1. 安装到你的 dsh profile
dsh plugin --profile desktop add dsh-maclens

# 2. 重启 DSH，然后直接对模型说：
#    "OCR 这张截图：/Users/me/Desktop/shot.png"
```

**模型可以调用的五个工具：**

| 工具 | 一句话说明 |
|---|---|
| `maclens_ocr` | "读出这张图的所有文字" — 每行文字 + 置信度 + 坐标框 |
| `maclens_classify` | "这是什么类型的图？" — 文档、图表、照片… |
| `maclens_faces` | "图里有人吗？" — 人脸框 + 数量 |
| `maclens_document` | "解析这一页" — OCR + 左右双栏版面 |
| `maclens_describe` | "一次性全给我" — OCR + 分类 + 人脸 + 版面 |

**maclens 与 VLM 怎么选：** maclens 是 CV 工具箱——负责*转写、分类、检测*，但**不会**描述"这张图讲了什么"。需要开放式理解？搭配 VLM 桥（如 modlens + qwen-vl）。需要快速、免费、私密的 OCR/检测？用 maclens。

---

## 🤖 Agent 读者 — 精确契约

### 一句话摘要

```text
插件：    dsh-maclens（npm），dsh plugin add 安装
运行时：  macOS 14+，需要 Xcode Command Line Tools（Swift 6+）
工具：    maclens_ocr | maclens_classify | maclens_faces | maclens_document | maclens_describe
输入：    绝对本地图片路径（string）— 每个工具必填
输出：    stdout 上一个 JSON 对象；失败时 {"error": "..."} + 退出码 1
二进制：  包内 bin/maclens（自动 chmod），否则 MACLENS_BIN，否则 PATH
无网络：  CLI 零网络请求
```

### 安装（精确命令）

```sh
# 从 npm 安装 — 含预编译二进制，无需构建：
dsh plugin --profile desktop add dsh-maclens

# 从 git 检出 — 先构建 Swift 桥：
cd dsh-maclens && bash scripts/build.sh        # 生成 bin/maclens
dsh plugin --profile desktop add ./dsh-maclens
```

二进制解析顺序：包内 `bin/maclens` → `$MACLENS_BIN` → `swift/.build/release/MaclensBridge` → PATH 上的 `maclens`。插件在解析时会把二进制 chmod 为 `0755`（npm tarball 会丢执行位）。

### 工具参数

五个工具都接受 `path`（必填，string）。OCR 系工具额外支持：

| 字段 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `languages` | string | `zh-Hans,en-US` | 逗号分隔的识别语言 |
| `maxLines` | number | — | 限制返回的 OCR 行数（超大截图） |
| `slice` | boolean | false | 把长图切成重叠条带再 OCR |
| `sliceHeight` | number | 4096 | 切片条带高度（像素） |
| `top` | number | 5 | 仅 classify：返回几个分类 |

### 输出契约

`maclens_ocr` 返回：

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

- `bbox` 是**归一化**（0–1），原点**左上**（已从 Vision 的右下原点转换，直观易用）。
- `slice: true` 时，长图切成重叠条带、逐条 OCR、拼回整图坐标，重叠区的重复行去重。输出追加 `"sliced": true` 与 `"slice_count": N`。
- `maclens_document` = `ocr` + `layout.columns`（左右）+ `layout.image_dimensions`。
- `maclens_describe` = `ocr` + `classification.observations` + `faces` + `layout`。
- `maclens_faces` → `faces[]` + `face_count`；`maclens_classify` → `observations[]`（`identifier`、`confidence`）。

### 错误契约

| 退出码 | 含义 |
|---|---|
| 0 | 成功 |
| 1 | 运行时错误 — stdout 是 `{"error": "..."}`（如 `file does not exist: <path>`） |
| 2 | 用法/未知任务 — stdout 是 `{"error": "usage: ..."}` |

### 原始 CLI（dsh 外调试用）

```sh
bin/maclens ocr --image /path/to/img.png
bin/maclens classify --image /path/to/img.png --top 3
bin/maclens faces --image /path/to/img.png
bin/maclens document --image /path/to/img.png --slice
bin/maclens describe --image /path/to/img.png --slice --top 2
```

---

## 🏗️ 工作原理

```
dsh（纯文本模型）
  └─ maclens_* 工具（lib/index.js）
       └─ bin/maclens（Swift CLI，每次调用 spawn — 无常驻进程、无端口）
            └─ Apple Vision：VNRecognizeTextRequest / VNClassifyImageRequest /
               VNDetectFaceRectanglesRequest        ← 设备端、离线
```

## 🧪 开发

```sh
cd swift && swift build -c release
swift test --package-path swift      # 6 个行为测试
```

CI（GitHub Actions）：macOS 上 Swift release 构建 + 冒烟测试；Ubuntu 上插件加载 + 打包内容检查。`main` 分支全绿。

## 📄 文档

- [`AGENTS.md`](AGENTS.md) — agent 专用快速参考。
- [`CHANGELOG.md`](CHANGELOG.md) — 版本历史。
- [`SECURITY.md`](SECURITY.md) — 安全模型与报告。

## 许可

MIT — 见 [LICENSE](LICENSE)。
