#!/usr/bin/swift
import Vision
import Foundation
import AppKit

guard CommandLine.arguments.count > 1 else {
    print("usage: ocr <image>")
    exit(1)
}
let path = CommandLine.arguments[1]
guard let img = NSImage(contentsOfFile: path),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("cannot load image")
    exit(1)
}
let request = VNRecognizeTextRequest { req, err in
    guard let obs = req.results as? [VNRecognizedTextObservation] else { return }
    for o in obs {
        if let t = o.topCandidates(1).first {
            print(t.string)
        }
    }
}
request.recognitionLanguages = ["zh-Hans", "en-US"]
request.recognitionLevel = .accurate
let handler = VNImageRequestHandler(cgImage: cg, options: [:])
try handler.perform([request])
