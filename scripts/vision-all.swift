#!/usr/bin/swift
import Vision
import Foundation
import AppKit
import CoreGraphics

// mac-vision: 四合一本地视觉识别 (macOS 26)
// 并行执行: 文字识别 + 文字区域检测 + 物体检测 + 图像分类
// 用法: vision-all.swift <图片路径> [--json]

let args = CommandLine.arguments
guard args.count > 1 else {
    print("usage: vision-all <image> [--json]")
    exit(1)
}
let path = args[1]
let asJson = args.contains("--json")

guard let img = NSImage(contentsOfFile: path),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("cannot load image: \(path)")
    exit(1)
}

// 置信度阈值
let textThreshold: Float = 0.5
let textRegionThreshold: Float = 0.3
let objectThreshold: Float = 0.25

// 结果结构
struct TextLine { let string: String; let conf: Float }
struct TextRegion { let x: Double; let y: Double; let w: Double; let h: Double; let conf: Float }
struct ObjectHit { let label: String; let conf: Float; let x: Double; let y: Double; let w: Double; let h: Double }
struct ClassHit { let label: String; let conf: Float }

var texts: [TextLine] = []
var textRegions: [TextRegion] = []
var objects: [ObjectHit] = []
var classes: [ClassHit] = []
var textFiltered = 0
var textRegionFiltered = 0
var objectFiltered = 0
var classFiltered = 0

// --- ① 文字识别 ---
let textReq = VNRecognizeTextRequest { req, _ in
    guard let results = req.results as? [VNRecognizedTextObservation] else { return }
    for o in results {
        guard let c = o.topCandidates(1).first else { continue }
        if c.confidence >= textThreshold {
            texts.append(TextLine(string: c.string, conf: c.confidence))
        } else {
            textFiltered += 1
        }
    }
}
textReq.recognitionLanguages = ["zh-Hans", "en-US"]
textReq.recognitionLevel = .accurate

// --- ② 文字区域检测（定位图中所有文字块的位置）---
let textRegionReq = VNDetectTextRectanglesRequest { req, _ in
    guard let results = req.results as? [VNTextObservation] else { return }
    for o in results {
        if o.confidence >= textRegionThreshold {
            let b = o.boundingBox
            textRegions.append(TextRegion(x: b.origin.x, y: b.origin.y, w: b.size.width, h: b.size.height, conf: o.confidence))
        } else {
            textRegionFiltered += 1
        }
    }
}
textRegionReq.reportCharacterBoxes = false

// --- ③ 图像分类（官方推荐 hasMinimumPrecision 过滤）---
let classifyReq = VNClassifyImageRequest { req, _ in
    guard let results = req.results as? [VNClassificationObservation] else { return }
    // 高召回过滤：保留官方认为"属于这张图"的标签，避免上千个垃圾候选
    for o in results {
        if o.hasMinimumPrecision(0.1, forRecall: 0.8) {
            classes.append(ClassHit(label: o.identifier, conf: o.confidence))
        } else {
            classFiltered += 1
        }
    }
}

// --- ④ 物体检测（ObjC 动态派发，编译期类型被 SDK 隐藏但运行时可用）---
do {
    if let objCls = NSClassFromString("VNRecognizeObjectsRequest") as? VNRequest.Type {
        let objReq = objCls.init()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try handler.perform([objReq])
        // perform 后直接读 results 属性
        if let results = objReq.results as? [VNRecognizedObjectObservation] {
            for o in results {
                for l in o.labels {
                    if l.confidence >= objectThreshold {
                        let b = o.boundingBox
                        objects.append(ObjectHit(label: l.identifier, conf: l.confidence,
                                                 x: b.origin.x, y: b.origin.y, w: b.size.width, h: b.size.height))
                    } else {
                        objectFiltered += 1
                    }
                }
            }
        }
    }
} catch {
    // 物体检测失败不阻断其他检测
}

// --- 并行执行其余请求（除物体检测已单独跑）---
let handler = VNImageRequestHandler(cgImage: cg, options: [:])
try handler.perform([textReq, textRegionReq, classifyReq])

// --- 输出 ---
if asJson {
    let jsonObj: [String: Any] = [
        "text": texts.map { ["string": $0.string, "confidence": $0.conf] },
        "textRegions": textRegions.map { ["x": $0.x, "y": $0.y, "w": $0.w, "h": $0.h, "confidence": $0.conf] },
        "objects": objects.map { ["label": $0.label, "confidence": $0.conf, "x": $0.x, "y": $0.y, "w": $0.w, "h": $0.h] },
        "classes": classes.map { ["label": $0.label, "confidence": $0.conf] },
        "filtered": ["text": textFiltered, "textRegion": textRegionFiltered, "object": objectFiltered, "class": classFiltered]
    ]
    if let data = try? JSONSerialization.data(withJSONObject: jsonObj, options: [.prettyPrinted, .sortedKeys]),
       let str = String(data: data, encoding: .utf8) {
        print(str)
    }
} else {
    // 文字
    print("📄 文字: ", terminator: "")
    if texts.isEmpty {
        print("未识别到文字")
    } else {
        print("\(texts.count) 行")
        for t in texts {
            print("   \(t.string)  (\(String(format: "%.2f", t.conf)))")
        }
    }
    if textFiltered > 0 { print("   ⚠️ 已过滤 \(textFiltered) 个低置信度文字块") }

    // 文字区域
    print("📐 文字区域: ", terminator: "")
    if textRegions.isEmpty {
        print("未检测到文字区域")
    } else {
        print("\(textRegions.count) 个")
        for r in textRegions {
            print("   区域 位置(\(String(format: "%.3f", r.x)), \(String(format: "%.3f", r.y))) 大小\(String(format: "%.2f", r.w))x\(String(format: "%.2f", r.h))  (\(String(format: "%.2f", r.conf)))")
        }
    }
    if textRegionFiltered > 0 { print("   ⚠️ 已过滤 \(textRegionFiltered) 个低置信度文字区域") }

    // 物体
    print("📦 物体: ", terminator: "")
    if objects.isEmpty {
        print("未识别到常见物体")
    } else {
        print("\(objects.count) 个")
        for o in objects {
            print("   \(o.label)  (\(String(format: "%.2f", o.conf)))")
        }
    }
    if objectFiltered > 0 { print("   ⚠️ 已过滤 \(objectFiltered) 个低置信度物体") }

    // 分类
    print("🏷 分类: ", terminator: "")
    if classes.isEmpty {
        print("置信度过低，无有效标签")
    } else {
        print("\(classes.count) 个候选")
        for c in classes {
            print("   \(c.label)  (\(String(format: "%.2f", c.conf)))")
        }
    }
    if classFiltered > 0 { print("   ⚠️ 已过滤 \(classFiltered) 个低置信度分类标签") }
}