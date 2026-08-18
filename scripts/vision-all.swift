#!/usr/bin/swift
import Vision
import Foundation
import AppKit
import CoreGraphics

// mac-vision: 五合一本地视觉识别 (macOS 26)
// 并行执行: 文字识别 + 人脸检测 + 人体检测 + 物体检测 + 图像分类
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
let faceThreshold: Float = 0.5
let humanThreshold: Float = 0.4
let objectThreshold: Float = 0.25

// 结果结构
struct TextLine { let string: String; let conf: Float }
struct FaceBox { let x: Double; let y: Double; let w: Double; let h: Double; let conf: Float }
struct HumanBox { let x: Double; let y: Double; let w: Double; let h: Double; let conf: Float }
struct ObjectHit { let label: String; let conf: Float; let x: Double; let y: Double; let w: Double; let h: Double }
struct ClassHit { let label: String; let conf: Float }

var texts: [TextLine] = []
var faces: [FaceBox] = []
var humans: [HumanBox] = []
var objects: [ObjectHit] = []
var classes: [ClassHit] = []
var textFiltered = 0
var faceFiltered = 0
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

// --- ② 人脸检测 ---
let faceReq = VNDetectFaceRectanglesRequest { req, _ in
    guard let results = req.results as? [VNFaceObservation] else { return }
    for o in results {
        if o.confidence >= faceThreshold {
            let b = o.boundingBox
            faces.append(FaceBox(x: b.origin.x, y: b.origin.y, w: b.size.width, h: b.size.height, conf: o.confidence))
        } else {
            faceFiltered += 1
        }
    }
}

// --- ③ 人体检测 ---
let humanReq = VNDetectHumanRectanglesRequest { req, _ in
    guard let results = req.results as? [VNHumanObservation] else { return }
    for o in results {
        if o.confidence >= humanThreshold {
            let b = o.boundingBox
            humans.append(HumanBox(x: b.origin.x, y: b.origin.y, w: b.size.width, h: b.size.height, conf: o.confidence))
        }
    }
}

// --- ④ 图像分类（官方推荐 hasMinimumPrecision 过滤）---
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

// --- ⑤ 物体检测（ObjC 动态派发，编译期类型被 SDK 隐藏但运行时可用）---
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
try handler.perform([textReq, faceReq, humanReq, classifyReq])

// --- 输出 ---
if asJson {
    let jsonObj: [String: Any] = [
        "text": texts.map { ["string": $0.string, "confidence": $0.conf] },
        "faces": faces.map { ["x": $0.x, "y": $0.y, "w": $0.w, "h": $0.h, "confidence": $0.conf] },
        "humans": humans.map { ["x": $0.x, "y": $0.y, "w": $0.w, "h": $0.h, "confidence": $0.conf] },
        "objects": objects.map { ["label": $0.label, "confidence": $0.conf, "x": $0.x, "y": $0.y, "w": $0.w, "h": $0.h] },
        "classes": classes.map { ["label": $0.label, "confidence": $0.conf] },
        "filtered": ["text": textFiltered, "face": faceFiltered, "object": objectFiltered, "class": classFiltered]
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

    // 人脸
    print("👤 人脸: ", terminator: "")
    if faces.isEmpty {
        print("未检测到人脸")
    } else {
        print("\(faces.count) 张")
        for f in faces {
            print("   脸 位置(\(String(format: "%.3f", f.x)), \(String(format: "%.3f", f.y))) 大小\(String(format: "%.2f", f.w))x\(String(format: "%.2f", f.h))  (\(String(format: "%.2f", f.conf)))")
        }
    }
    if faceFiltered > 0 { print("   ⚠️ 已过滤 \(faceFiltered) 个低置信度人脸") }

    // 人体
    print("🧍 人体: ", terminator: "")
    if humans.isEmpty {
        print("未检测到人体")
    } else {
        print("\(humans.count) 人")
        for h in humans {
            print("   人 位置(\(String(format: "%.3f", h.x)), \(String(format: "%.3f", h.y)))  (\(String(format: "%.2f", h.conf)))")
        }
    }

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