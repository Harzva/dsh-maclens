// MaclensBridgeTests — behavioral tests for the maclens CLI.
//
// These run the compiled binary as a subprocess against a small generated
// PNG and assert the JSON contract (task key present, valid JSON, sane
// error paths). The Vision framework does the real work, so the tests
// document what dsh-maclens relies on rather than re-implementing Vision.

import Foundation
import Testing

struct MaclensBridgeTests {

    /// Generate a tiny valid PNG (white with a black block) so tests do not
    /// depend on fixture files.
    func makeTestPNG() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("maclens-test-\(UUID().uuidString).png")
        var raw = Data()
        let w = 64, h = 64
        for y in 0..<h {
            raw.append(0) // filter byte
            for x in 0..<w {
                if x < 16 && y < 16 {
                    raw.append(contentsOf: [0, 0, 0]) // black block
                } else {
                    raw.append(contentsOf: [255, 255, 255])
                }
            }
        }

        func chunk(_ type: String, _ data: Data) -> Data {
            var out = Data()
            out.append(contentsOf: withUnsafeBytes(of: UInt32(data.count).bigEndian) { Data($0) })
            out.append(Data(type.utf8))
            out.append(data)
            var crcBE = crc32(Data(type.utf8) + data).bigEndian
            out.append(contentsOf: withUnsafeBytes(of: &crcBE) { Data($0) })
            return out
        }

        var ihdr = Data()
        ihdr.append(contentsOf: withUnsafeBytes(of: UInt32(w).bigEndian) { Data($0) })
        ihdr.append(contentsOf: withUnsafeBytes(of: UInt32(h).bigEndian) { Data($0) })
        ihdr.append(contentsOf: [8, 2, 0, 0, 0]) // bit depth, color type, compression, filter, interlace

        var png = Data()
        png.append(contentsOf: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        png.append(chunk("IHDR", ihdr))
        png.append(chunk("IDAT", raw))
        png.append(chunk("IEND", Data()))

        try png.write(to: url)
        return url
    }

    func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1
            }
            table[i] = c
        }
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    func runCLI(_ arguments: [String]) throws -> (code: Int32, stdout: String, stderr: String) {
        // The test runner does not inherit arbitrary env vars, so locate the
        // built binary relative to the package root (tests run with CWD =
        // package root) with an env override as a fallback.
        let candidates = [
            ProcessInfo.processInfo.environment["MACLENS_TEST_BIN"],
            ".build/release/MaclensBridge",
            FileManager.default.currentDirectoryPath + "/.build/release/MaclensBridge",
        ].compactMap { $0 }
        guard let bin = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw TestError.missingBinary
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            throw TestError.spawnFailed(bin, error)
        }
        process.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, out, err)
    }

    enum TestError: Error, CustomStringConvertible {
        case missingBinary
        case spawnFailed(String, Error)
        case badJSON(String)

        var description: String {
            switch self {
            case .missingBinary:
                return "maclens binary not found (build with: swift build -c release)"
            case .spawnFailed(let bin, let error):
                return "spawn failed for \(bin): \(error)"
            case .badJSON(let raw):
                return "non-JSON output: \(raw.prefix(200))"
            }
        }
    }

    func parseJSON(_ out: String) throws -> [String: Any] {
        guard let json = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any] else {
            throw TestError.badJSON(out)
        }
        return json
    }

    @Test func unknownTaskExits2() throws {
        let (code, out, _) = try runCLI(["nonsense", "--image", "/tmp/x.png"])
        #expect(code == 2)
        let json = try parseJSON(out)
        #expect(json["error"] != nil)
    }

    @Test func missingImageExits1WithMessage() throws {
        let (code, out, _) = try runCLI(["ocr", "--image", "/tmp/definitely-missing.png"])
        #expect(code == 1)
        let json = try parseJSON(out)
        let error = json["error"] as? String ?? ""
        #expect(error.contains("does not exist"))
    }

    @Test func ocrProducesValidContract() throws {
        let png = try makeTestPNG()
        defer { try? FileManager.default.removeItem(at: png) }
        let (code, out, _) = try runCLI(["ocr", "--image", png.path])
        #expect(code == 0)
        let json = try parseJSON(out)
        #expect(json["task"] as? String == "ocr")
        #expect(json["lines"] is [Any])
        #expect(json["full_text"] is String)
        #expect(json["line_count"] is Int)
    }

    @Test func classifyProducesObservations() throws {
        let png = try makeTestPNG()
        defer { try? FileManager.default.removeItem(at: png) }
        let (code, out, _) = try runCLI(["classify", "--image", png.path, "--top", "3"])
        #expect(code == 0)
        let json = try parseJSON(out)
        #expect(json["task"] as? String == "classify")
        #expect(json["observations"] is [Any])
    }

    @Test func facesProducesCount() throws {
        let png = try makeTestPNG()
        defer { try? FileManager.default.removeItem(at: png) }
        let (code, out, err) = try runCLI(["faces", "--image", png.path])
        if code != 0 { print("DIAG faces stderr:", err); print("DIAG faces stdout:", out) }
        #expect(code == 0)
        let json = try parseJSON(out)
        #expect(json["task"] as? String == "faces")
        #expect(json["face_count"] is Int)
    }

    @Test func describeCombinesAll() throws {
        let png = try makeTestPNG()
        defer { try? FileManager.default.removeItem(at: png) }
        let (code, out, _) = try runCLI(["describe", "--image", png.path, "--top", "2"])
        #expect(code == 0)
        let json = try parseJSON(out)
        #expect(json["task"] as? String == "describe")
        #expect(json["ocr"] != nil)
        #expect(json["classification"] != nil)
        #expect(json["faces"] != nil)
        #expect(json["layout"] != nil)
    }
}
