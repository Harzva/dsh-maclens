// MaclensBridge — a local Vision-framework bridge for dsh-maclens.
//
// A tiny Swift CLI that runs Apple's on-device Vision framework over one
// image and prints structured JSON to stdout. dsh-maclens (the DSH plugin)
// spawns this binary; nothing here talks to the network.
//
// Usage:
//   maclens ocr      --image <path> [--languages zh-Hans,en-US] [--max-lines N]
//   maclens classify --image <path> [--top 5]
//   maclens faces    --image <path>
//   maclens document --image <path> [--languages zh-Hans,en-US] [--max-lines N]
//   maclens describe --image <path> [--languages zh-Hans,en-US] [--top 5] [--max-lines N]
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
    var maxLines: Int? = nil
    var slice: Bool = false
    var sliceHeight: Int = 4096
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
        case "--max-lines":
            i += 1
            guard i < argv.count, let n = Int(argv[i]), n > 0 else { return nil }
            args.maxLines = n
        case "--slice":
            args.slice = true
        case "--slice-height":
            i += 1
            guard i < argv.count, let n = Int(argv[i]), n > 0 else { return nil }
            args.sliceHeight = n
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
    guard FileManager.default.fileExists(atPath: path) else {
        throw NSError(domain: "maclens", code: 3, userInfo: [NSLocalizedDescriptionKey: "file does not exist: \(path)"])
    }
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

// MARK: - Tall-image slicing

/// Crop a horizontal strip of `height` pixels starting at `y` (top-left
/// origin, pixel units) from `image` and return it as a new CGImage.
func cropStrip(from image: CGImage, y: Int, height: Int) -> CGImage? {
    let w = image.width
    let h = image.height
    let safeH = max(0, min(height, h - y))
    guard safeH > 0 else { return nil }
    return image.cropping(to: CGRect(x: 0, y: y, width: w, height: safeH))
}

/// OCR a tall image by splitting it into overlapping horizontal strips.
/// Vision can miss or mis-order text on very tall screenshots (its internal
/// downscale loses small text), so we run each strip separately and stitch
/// the results back into image coordinates. Returns the same shape as
/// runOCR, plus a `sliced` flag.
func runOCRWithSlicing(image: CGImage, languages: [String], maxLines: Int?, sliceHeight: Int) throws -> [String: Any] {
    let h = image.height
    let w = image.width
    if h <= sliceHeight {
        var plain = try runOCR(image: image, languages: languages, maxLines: maxLines)
        plain["sliced"] = false
        return plain
    }

    // Overlap by 10% so a line that straddles a cut is seen whole in at
    // least one strip.
    let overlap = max(1, sliceHeight / 10)
    let step = max(1, sliceHeight - overlap)
    var strips: [(offsetY: Int, stripH: Int)] = []
    var y = 0
    while y < h {
        let stripH = min(sliceHeight, h - y)
        strips.append((y, stripH))
        if y + stripH >= h { break }
        y += step
    }

    var allLines: [[String: Any]] = []
    var textParts: [String] = []
    for strip in strips {
        guard let cropped = cropStrip(from: image, y: strip.offsetY, height: strip.stripH) else { continue }
        let partial = try runOCR(image: cropped, languages: languages, maxLines: nil)
        let lines = partial["lines"] as! [[String: Any]]
        // Vision bboxes are normalized to the *strip*, origin bottom-left.
        // Convert to whole-image normalized coords, origin top-left to match
        // the single-shot output convention we document (Vision's native
        // bottom-left origin is confusing; keep one convention everywhere).
        let stripH = Double(strip.stripH)
        let imgH = Double(h)
        for line in lines {
            var box = line["bbox"] as! [String: Any]
            let bx = box["x"] as! Double
            let by = box["y"] as! Double
            let bw = box["width"] as! Double
            let bh = box["height"] as! Double
            // strip-local bottom-left -> whole-image top-left
            let topInStrip = 1.0 - (by + bh)
            let topInImage = (Double(strip.offsetY) + topInStrip * stripH) / imgH
            box["x"] = bx
            box["y"] = topInImage
            box["width"] = bw
            box["height"] = bh * (stripH / imgH)
            var newLine = line
            newLine["bbox"] = box
            newLine["slice"] = strip.offsetY
            allLines.append(newLine)
        }
        let text = partial["full_text"] as? String ?? ""
        if !text.isEmpty { textParts.append(text) }
    }

    // De-duplicate lines that appear in the overlap of two strips: a line
    // whose text matches another at a nearly identical y (within the overlap
    // band) is the same physical line seen twice — keep the first copy.
    // Identical text at clearly different heights is intentional repetition
    // in the image and is preserved.
    var unique: [[String: Any]] = []
    let sortedLines = allLines.sorted { (a, b) in
        let aBox = a["bbox"] as! [String: Any]
        let bBox = b["bbox"] as! [String: Any]
        return (aBox["y"] as! Double) < (bBox["y"] as! Double)
    }
    let overlapFraction = Double(overlap) / Double(sliceHeight)
    for line in sortedLines {
        let text = line["text"] as? String ?? ""
        let box = line["bbox"] as! [String: Any]
        let y = box["y"] as! Double
        let duplicate = unique.contains { existing in
            guard (existing["text"] as? String) == text else { return false }
            let eBox = existing["bbox"] as! [String: Any]
            return abs((eBox["y"] as! Double) - y) < overlapFraction
        }
        if duplicate { continue }
        unique.append(line)
    }
    if let maxLines = maxLines, unique.count > maxLines {
        unique = Array(unique.prefix(maxLines))
    }

    return [
        "task": "ocr",
        "language": languages,
        "full_text": textParts.joined(separator: "\n"),
        "lines": unique,
        "line_count": unique.count,
        "truncated": maxLines != nil && unique.count >= (maxLines ?? 0),
        "sliced": true,
        "slice_count": strips.count,
    ]
}

// MARK: - OCR

func runOCR(image: CGImage, languages: [String], maxLines: Int? = nil) throws -> [String: Any] {
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
    if let maxLines = maxLines, lines.count > maxLines {
        lines = Array(lines.prefix(maxLines))
        fullText = Array(fullText.prefix(maxLines))
    }
    return [
        "task": "ocr",
        "language": languages,
        "full_text": fullText.joined(separator: "\n"),
        "lines": lines,
        "line_count": lines.count,
        "truncated": maxLines != nil && lines.count >= (maxLines ?? 0),
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

/// Build the simple left/right column layout summary from OCR lines.
func layoutFor(image: CGImage, lines: [[String: Any]]) -> [String: Any] {
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
    return [
        "columns": [
            ["side": "left", "text": leftCol.joined(separator: " ")],
            ["side": "right", "text": rightCol.joined(separator: " ")],
        ].filter { !($0["text"] as! String).isEmpty },
        "image_dimensions": ["width": width, "height": Double(image.height)],
    ]
}

func runDocument(image: CGImage, languages: [String], maxLines: Int? = nil) throws -> [String: Any] {
    let ocr = try runOCR(image: image, languages: languages, maxLines: maxLines)
    var result = ocr
    result["task"] = "document"
    result["layout"] = layoutFor(image: image, lines: result["lines"] as! [[String: Any]])
    return result
}

// MARK: - Combined describe (OCR + classify + faces + layout)

func runDescribe(image: CGImage, languages: [String], top: Int, maxLines: Int?) throws -> [String: Any] {
    let ocr = try runOCR(image: image, languages: languages, maxLines: maxLines)
    let classify = try runClassify(image: image, top: top)
    let faces = try runFaces(image: image)
    let doc = try runDocument(image: image, languages: languages, maxLines: maxLines)
    let layout = doc["layout"] as? [String: Any] ?? [:]
    return [
        "task": "describe",
        "image_dimensions": layout["image_dimensions"] ?? [:],
        "ocr": ocr,
        "classification": classify,
        "faces": faces,
        "layout": layout,
    ]
}

// MARK: - Main

func main() -> Int32 {
    let argv = CommandLine.arguments
    guard let args = parseArgs(argv) else {
        print(jsonString(["error": "usage: maclens <ocr|classify|faces|document|describe> --image <path> [--languages a,b] [--top N] [--max-lines N] [--slice] [--slice-height N]"]))
        return 2
    }
    let validTasks = ["ocr", "classify", "faces", "document", "describe"]
    guard validTasks.contains(args.task) else {
        print(jsonString(["error": "unknown task: \(args.task)"]))
        return 2
    }
    do {
        let image = try loadCGImage(path: args.imagePath)
        let result: [String: Any]
        switch args.task {
        case "ocr":
            if args.slice {
                result = try runOCRWithSlicing(image: image, languages: args.languages, maxLines: args.maxLines, sliceHeight: args.sliceHeight)
            } else {
                result = try runOCR(image: image, languages: args.languages, maxLines: args.maxLines)
            }
        case "classify":
            result = try runClassify(image: image, top: args.top)
        case "faces":
            result = try runFaces(image: image)
        case "document":
            if args.slice {
                let sliced = try runOCRWithSlicing(image: image, languages: args.languages, maxLines: args.maxLines, sliceHeight: args.sliceHeight)
                var doc = sliced
                doc["task"] = "document"
                doc["layout"] = try layoutFor(image: image, lines: sliced["lines"] as! [[String: Any]])
                result = doc
            } else {
                result = try runDocument(image: image, languages: args.languages, maxLines: args.maxLines)
            }
        case "describe":
            if args.slice {
                let sliced = try runOCRWithSlicing(image: image, languages: args.languages, maxLines: args.maxLines, sliceHeight: args.sliceHeight)
                let classify = try runClassify(image: image, top: args.top)
                let faces = try runFaces(image: image)
                let layout = try layoutFor(image: image, lines: sliced["lines"] as! [[String: Any]])
                result = [
                    "task": "describe",
                    "image_dimensions": ["width": Double(image.width), "height": Double(image.height)],
                    "ocr": sliced,
                    "classification": classify,
                    "faces": faces,
                    "layout": layout,
                ]
            } else {
                result = try runDescribe(image: image, languages: args.languages, top: args.top, maxLines: args.maxLines)
            }
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
