// MaclensBridge — a local Vision-framework bridge for dsh-maclens.
//
// A tiny Swift CLI that runs Apple's on-device Vision framework over one
// image and prints structured JSON to stdout. dsh-maclens (the DSH plugin)
// spawns this binary; nothing here talks to the network.
//
// Usage:
//   maclens ocr      --image <path> [--languages zh-Hans,en-US]
//   maclens classify --image <path> [--top 5]
//   maclens faces    --image <path>
//   maclens document --image <path> [--languages zh-Hans,en-US]
//
// Output: one JSON object on stdout, errors as {"error": "..."} with exit 1.

import Foundation
import Vision
import ImageIO

// MARK: - Argument parsing (no external deps)

struct Args {
    var task: String = ""
    var imagePath: String = ""
    var languages: [String] = ["zh-Hans", "en-US"]
    var top: Int = 5
}

func parseArgs(_ argv: [String]) -> Args? {
    var args = Args()
    var i = 1
    var positional: [String] = []
    while i < argv.count {
        let token = argv[i]
        switch token {
        case "--image":
            i += 1
            guard i < argv.count else { return nil }
            args.imagePath = argv[i]
        case "--languages":
            i += 1
            guard i < argv.count else { return nil }
            args.languages = argv[i].split(separator: ",").map(String.init)
        case "--top":
            i += 1
            guard i < argv.count, let n = Int(argv[i]) else { return nil }
            args.top = n
        default:
            if token.hasPrefix("-") { return nil }
            positional.append(token)
        }
        i += 1
    }
    guard positional.count == 1 else { return nil }
    args.task = positional[0]
    return args
}

// MARK: - Image loading

func loadCGImage(path: String) throws -> CGImage {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        throw NSError(domain: "maclens", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot open image: \(path)"])
    }
    guard let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        throw NSError(domain: "maclens", code: 2, userInfo: [NSLocalizedDescriptionKey: "cannot decode image: \(path)"])
    }
    return cg
}

// MARK: - JSON helpers

func jsonString(_ value: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
        return "{\"error\":\"json serialization failed\"}"
    }
    return String(data: data, encoding: .utf8) ?? "{}"
}

// MARK: - OCR

func runOCR(image: CGImage, languages: [String]) throws -> [String: Any] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = languages

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])

    var lines: [[String: Any]] = []
    var fullText: [String] = []
    for obs in request.results ?? [] {
        guard let candidate = obs.topCandidates(1).first else { continue }
        let box = obs.boundingBox // normalized, origin bottom-left
        let line: [String: Any] = [
            "text": candidate.string,
            "confidence": candidate.confidence,
            "bbox": [
                "x": Double(box.origin.x),
                "y": Double(box.origin.y),
                "width": Double(box.size.width),
                "height": Double(box.size.height),
            ],
        ]
        lines.append(line)
        fullText.append(candidate.string)
    }
    // Sort top-to-bottom, then left-to-right (Vision bbox origin is bottom-left).
    lines.sort { a, b in
        let ay = (a["bbox"] as! [String: Any])["y"] as! Double
        let by = (b["bbox"] as! [String: Any])["y"] as! Double
        if abs(ay - by) > 0.02 { return ay > by }
        let ax = (a["bbox"] as! [String: Any])["x"] as! Double
        let bx = (b["bbox"] as! [String: Any])["x"] as! Double
        return ax < bx
    }
    return [
        "task": "ocr",
        "language": languages,
        "full_text": fullText.joined(separator: "\n"),
        "lines": lines,
        "line_count": lines.count,
    ]
}

// MARK: - Classification

func runClassify(image: CGImage, top: Int) throws -> [String: Any] {
    let request = VNClassifyImageRequest()
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])

    var observations: [[String: Any]] = []
    for obs in (request.results ?? []).prefix(top) {
        observations.append([
            "identifier": obs.identifier,
            "confidence": obs.confidence,
        ])
    }
    return [
        "task": "classify",
        "observations": observations,
    ]
}

// MARK: - Face detection

func runFaces(image: CGImage) throws -> [String: Any] {
    let request = VNDetectFaceRectanglesRequest()
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])

    var faces: [[String: Any]] = []
    for obs in request.results ?? [] {
        let box = obs.boundingBox
        faces.append([
            "bbox": [
                "x": Double(box.origin.x),
                "y": Double(box.origin.y),
                "width": Double(box.size.width),
                "height": Double(box.size.height),
            ],
            "confidence": obs.confidence,
        ])
    }
    return [
        "task": "faces",
        "faces": faces,
        "face_count": faces.count,
    ]
}

// MARK: - Document parsing (OCR + layout summary)

func runDocument(image: CGImage, languages: [String]) throws -> [String: Any] {
    let ocr = try runOCR(image: image, languages: languages)
    var result = ocr
    result["task"] = "document"
    // Estimate simple layout regions from text lines: group lines into
    // left/right columns when their x ranges barely overlap.
    let lines = (result["lines"] as! [[String: Any]])
    let width = Double(image.width)
    var leftCol: [String] = []
    var rightCol: [String] = []
    for line in lines {
        let box = line["bbox"] as! [String: Any]
        let x = box["x"] as! Double
        let w = box["width"] as! Double
        let mid = x + w / 2
        if mid < 0.5 { leftCol.append(line["text"] as! String) }
        else { rightCol.append(line["text"] as! String) }
    }
    result["layout"] = [
        "columns": [
            ["side": "left", "text": leftCol.joined(separator: " ")],
            ["side": "right", "text": rightCol.joined(separator: " ")],
        ].filter { !($0["text"] as! String).isEmpty },
        "image_dimensions": ["width": width, "height": Double(image.height)],
    ]
    return result
}

// MARK: - Main

func main() -> Int32 {
    let argv = CommandLine.arguments
    guard let args = parseArgs(argv) else {
        print(jsonString(["error": "usage: maclens <ocr|classify|faces|document> --image <path> [--languages a,b] [--top N]"]))
        return 2
    }
    do {
        let image = try loadCGImage(path: args.imagePath)
        let result: [String: Any]
        switch args.task {
        case "ocr":
            result = try runOCR(image: image, languages: args.languages)
        case "classify":
            result = try runClassify(image: image, top: args.top)
        case "faces":
            result = try runFaces(image: image)
        case "document":
            result = try runDocument(image: image, languages: args.languages)
        default:
            print(jsonString(["error": "unknown task: \(args.task)"]))
            return 2
        }
        print(jsonString(result))
        return 0
    } catch {
        print(jsonString(["error": error.localizedDescription]))
        return 1
    }
}

exit(main())
