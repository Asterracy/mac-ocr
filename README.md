# mac-ocr

> **⚠️ 仅 Mac 可用 (macOS Only)**
>
> 本 skill 依赖 macOS 内置的 Vision framework (`VNRecognizeTextRequest`),不适用于 Linux / Windows / WSL。

macOS Vision 本地 OCR skill — 让 AI Agent(如 opencode)直接调用系统 Vision framework 识别图片中的文字。**全程本地运行,不联网、不上传图片、免费、无 API key。**

## 功能

- **中英混合 OCR**:同时识别中文(`zh-Hans`)和英文(`en-US`),默认 `recognitionLevel = .accurate`
- **零依赖**:`swift` 解释器直接运行,不需要 pip install、不需要编译、不需要第三方库
- **本地隐私**:图片不出 Mac,可放心处理医学资料、论文、聊天截图等敏感内容
- **批量处理**:支持循环识别文件夹内多张图片
- **坐标定位**:可输出每个文字块的归一化坐标,用于按区域提取文字
- **双执行方式**:`ocr.swift`(解释执行,无构建)或 `ocr`(已编译二进制,更快)

## 安装

将整个目录放到 Agent 的 skill 发现目录:

```bash
mkdir -p ~/.agents/skills/mac-ocr
cp -r SKILL.md scripts/ ~/.agents/skills/mac-ocr/
```

支持 opencode、Claude Code、Codex 等遵循 agentskills.io 标准的 Agent。

## 使用

### 基本用法

```bash
# OCR 单张图片(解释执行)
swift ~/.agents/skills/mac-ocr/scripts/ocr.swift /path/to/image.png

# 或用已编译二进制(更快)
~/.agents/skills/mac-ocr/scripts/ocr /path/to/image.png
```

### 截图后识别

```bash
# macOS 内置截图(全屏/窗口/区域)
screencapture -x /tmp/ocr_snap.png
swift ~/.agents/skills/mac-ocr/scripts/ocr.swift /tmp/ocr_snap.png
```

### 批量识别

```bash
for f in ~/Desktop/screenshot/*.png; do
  echo "=== $f ==="
  swift ~/.agents/skills/mac-ocr/scripts/ocr.swift "$f"
done
```

## 技术原理

核心就三行 Vision framework API:

```swift
import Vision, Foundation, AppKit

// 1. 读取图片为 CGImage
let cg = NSImage(contentsOfFile: path)!.cgImage(...)!

// 2. 创建文字识别请求
let req = VNRecognizeTextRequest { r, _ in
    for o in (r.results as? [VNRecognizedTextObservation]) ?? [] {
        if let t = o.topCandidates(1).first { print(t.string) }
    }
}
req.recognitionLanguages = ["zh-Hans", "en-US"]

// 3. 执行
try VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
```

## 限制

- 识别顺序为视觉位置(从上到下),复杂排版可能顺序略乱
- 手写体准确率低,不推荐
- 纯英文长文可将 `recognitionLanguages` 改为 `["en-US"]` 提升速度

## License

MIT License — Copyright (c) 2026 Asterracy