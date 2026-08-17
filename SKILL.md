---
name: mac-ocr
description: >-
  macOS Vision framework 本地 OCR。当用户需要对图片/截图/扫描件进行文字识别、
  提取文字、读取图片内容、OCR 识别、翻译图片里的文字、把拍照内容转成文本、
  识别医学论文截图/讲义/网页截图中的文字时使用。
  全程本地运行，不联网、不传图片、免费、无 API key。
  支持中英文混合识别，可输出坐标定位文字块位置。
version: 1.0.0
---

# macOS Vision OCR

利用 macOS 自带 Vision framework（`VNRecognizeTextRequest`）实现本地 OCR。**零第三方依赖**，`swift` 解释器直接运行，不编译、不联网、不上传图片。

## 核心工具

| 脚本 | 用途 | 调用 |
|------|------|------|
| `ocr.swift` | 解释执行（推荐，无构建） | `swift <SKILL_DIR>/scripts/ocr.swift <图片>` |
| `ocr` | 已编译二进制（快，首次需编译） | `<SKILL_DIR>/scripts/ocr <图片>` |

> `<SKILL_DIR>` = 本 skill 所在目录 `~/.agents/skills/mac-ocr`

## 基本用法

```bash
# OCR 单张图片
swift ~/.agents/skills/mac-ocr/scripts/ocr.swift /path/to/image.png

# 识别中文为主的中英文混合（默认已含 zh-Hans + en-US）
# 识别结果按顺序输出到 stdout，每行一条文字
```

## 图片获取

无现成图片时，用 macOS 自带截图：

```bash
# 全屏截图到指定路径
screencapture -x /tmp/ocr_snap.png

# 窗口截图（需点击窗口）
screencapture -w -x /tmp/ocr_snap.png

# 区域截图（拖选区域）
screencapture -i -x /tmp/ocr_snap.png

# 静默全屏截图（截当前桌面，10 秒内可切窗口）
screencapture -x -T 5 /tmp/ocr_snap.png
```

截图后立即 OCR 该文件。

## 批量处理

```bash
# 识别文件夹内所有图片，逐张输出，文件名分隔
for f in ~/Desktop/screenshot/*.png; do
  echo "=== $f ==="
  swift ~/.agents/skills/mac-ocr/scripts/ocr.swift "$f"
done
```

## 高级：带坐标定位

需要知道文字在图片中的位置（坐标定位、按区域提取）时，可临时改用以下 Swift 片段，输出每个文字块的归一化坐标（原点在左下角）：

```swift
import Vision, Foundation, AppKit
guard CommandLine.arguments.count > 1, let img = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { exit(1) }
let req = VNRecognizeTextRequest { r, _ in
    for o in (r.results as? [VNRecognizedTextObservation]) ?? [] {
        if let t = o.topCandidates(1).first {
            let b = o.boundingBox
            print(String(format: "%.3f,%.3f,%.3f,%.3f\t%@", b.origin.x, b.origin.y, b.size.width, b.size.height, t.string))
        }
    }
}
req.recognitionLanguages = ["zh-Hans", "en-US"]
req.recognitionLevel = .accurate
try VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
```

## 参数调优参考

| 场景 | 建议 |
|------|------|
| 界面截图（UI 文字） | 默认 `.accurate` 即可 |
| 扫描件/拍照 | `.accurate` + 注意倾斜会降准 |
| 中英混合 | `recognitionLanguages = ["zh-Hans", "en-US"]`（默认） |
| 纯英文长文 | 可改 `["en-US"]` 提升速度 |
| 手写体 | 不推荐，准确率低 |

## 注意事项

- **全程本地**：图片不出 Mac，可放心处理隐私内容（医学资料、论文、聊天截图）
- **当前模型不支持直接看图**：识别结果以文本形式返回给用户核对
- 识别顺序为视觉位置（从上到下），非严格阅读顺序，复杂排版可能顺序略乱
- 若识别结果不全，可改用坐标输出版对照文字块位置排查
