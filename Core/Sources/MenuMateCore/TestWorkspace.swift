import Foundation
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO
import AVFoundation

public enum TestResource: String, CaseIterable, Sendable {
    case jpeg, png, tiff, gif, heic, text, sourceCode, pdf, archive, audio, video, folder, application

    public var type: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png: return .png
        case .tiff: return .tiff
        case .gif: return .gif
        case .heic: return .heic
        case .text: return .plainText
        case .sourceCode: return .swiftSource
        case .pdf: return .pdf
        case .archive: return .zip
        case .audio: return .wav
        case .video: return .mpeg4Movie
        case .folder: return .folder
        case .application: return .applicationBundle
        }
    }

    public var label: String {
        switch self {
        case .folder: return String(localized: "test.folderType", bundle: .module)
        case .application: return String(localized: "test.appType", bundle: .module)
        default: return type.preferredFilenameExtension?.uppercased() ?? rawValue
        }
    }

    public static func matching(_ rule: MatchRule) -> [TestResource] {
        if rule.targets == .container { return [.folder] }
        var typeRule = rule
        typeRule.minSelectionCount = nil
        typeRule.maxSelectionCount = nil
        return allCases.filter {
            RuleMatcher.evaluate(rule: typeRule, context: .items([
                MatchItem(isDirectory: $0 == .folder, contentType: $0.type)
            ])) == .matched
        }
    }
}

/// Disposable INPUTS, not a process sandbox. No user files are selected or copied.
/// Retain the workspace after a run so its generated outputs can be inspected.
public struct TestWorkspace: Sendable {
    public let directory: URL
    public let inputs: [URL]
    public let workingDirectory: URL
    public let dataDirectory: URL
    public let templatesDirectory: URL
    public var environment: [String: String] {
        ["MENUMATE_DATA": dataDirectory.path,
         "MENUMATE_TEMPLATES": templatesDirectory.path,
         "MENUMATE_TEST_RUN": "1",
         "MENUMATE_TEST_ROOT": directory.path,
         "TMPDIR": directory.appendingPathComponent("Temporary").path + "/"]
    }

    public enum Failure: LocalizedError {
        case unsupportedType, invalidCount, generation(String), mismatch, unsupportedVariantDirectory
        public var errorDescription: String? {
            switch self {
            case .unsupportedType: return String(localized: "test.unsupportedType", bundle: .module)
            case .invalidCount: return String(localized: "test.invalidCount", bundle: .module)
            case .generation(let message): return message
            case .mismatch: return String(localized: "test.sampleMismatch", bundle: .module)
            case .unsupportedVariantDirectory: return String(localized: "test.unsupportedVariantDirectory", bundle: .module)
            }
        }
    }

    public static func create(action: MenuAction, resource: TestResource, count: Int,
                              baseDirectory: URL = AppPaths.configDirectory()) throws -> TestWorkspace {
        guard (1...20).contains(count) else { throw Failure.invalidCount }
        guard TestResource.matching(action.matching).contains(resource) else { throw Failure.unsupportedType }
        try validateVariantSource(action.variants, baseDirectory: baseDirectory)
        let fm = FileManager.default
        let root = baseDirectory.appendingPathComponent("TestRuns", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let inputDir = root.appendingPathComponent("Inputs", isDirectory: true)
        let data = root.appendingPathComponent("Data", isDirectory: true)
        let templates = root.appendingPathComponent("Templates", isDirectory: true)
        do {
            for dir in [inputDir, data, templates, root.appendingPathComponent("Temporary")] {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            try "MenuMate temporary text template\n".write(to: templates.appendingPathComponent("Text.txt"), atomically: true, encoding: .utf8)
            try "# MenuMate\n\nTemporary Markdown template.\n".write(to: templates.appendingPathComponent("Markdown.md"), atomically: true, encoding: .utf8)
            var inputs: [URL] = []
            if action.matching.targets == .container {
                inputs = [inputDir]
            } else {
                for index in 1...count {
                    let url = inputDir.appendingPathComponent("Sample-\(index)")
                        .appendingPathExtension(resource.type.preferredFilenameExtension ?? "")
                    try write(resource, to: url)
                    inputs.append(url)
                }
            }
            // Exercise Paste Here without consuming the user's real cut buffer.
            if action.presetKey == "paste" {
                let seed = root.appendingPathComponent("PasteSource", isDirectory: true)
                try fm.createDirectory(at: seed, withIntermediateDirectories: true)
                let file = seed.appendingPathComponent("Sample.txt")
                try "MenuMate temporary paste sample\n".write(to: file, atomically: true, encoding: .utf8)
                try (file.path + "\n").write(to: data.appendingPathComponent("cutbuffer"), atomically: true, encoding: .utf8)
            }
            let context: MatchContext = action.matching.targets == .container ? .container(inputDir) : .items(inputs)
            guard RuleMatcher.matches(rule: action.matching, context: context) else { throw Failure.mismatch }
            return TestWorkspace(directory: root, inputs: inputs, workingDirectory: inputDir,
                                 dataDirectory: data, templatesDirectory: templates)
        } catch {
            try? fm.removeItem(at: root) // Only this freshly created UUID directory.
            throw error
        }
    }

    /// Only the standard template directory has an explicit generated-fixture contract.
    /// Never substitute generic templates for a user's unrelated directory.
    public static func validateVariantSource(_ source: VariantSource?, baseDirectory: URL) throws {
        guard case .directoryListing(let path) = source else { return }
        let resolved = path.hasPrefix("/") ? URL(fileURLWithPath: path) : baseDirectory.appendingPathComponent(path)
        guard resolved.standardizedFileURL.path == baseDirectory.appendingPathComponent("Templates").standardizedFileURL.path else {
            throw Failure.unsupportedVariantDirectory
        }
    }

    public func variants(for action: MenuAction) throws -> [String] {
        switch action.variants {
        case .fixed(let values): return values
        case .directoryListing:
            try Self.validateVariantSource(action.variants, baseDirectory: directory.deletingLastPathComponent().deletingLastPathComponent())
            return TemplateStore.list(in: templatesDirectory)
        case nil: return []
        }
    }

    private static func write(_ resource: TestResource, to url: URL) throws {
        switch resource {
        case .jpeg, .png, .tiff, .gif, .heic:
            guard let context = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
                  let destination = CGImageDestinationCreateWithURL(url as CFURL, resource.type.identifier as CFString, 1, nil)
            else { throw Failure.generation("Cannot create image sample.") }
            context.setFillColor(CGColor(red: 0.2, green: 0.45, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
            for index in 0..<12 {
                context.setFillColor(CGColor(red: CGFloat(index) / 12, green: 0.7, blue: 0.4, alpha: 1))
                context.fill(CGRect(x: index * 60, y: index * 35, width: 120, height: 180))
            }
            guard let image = context.makeImage() else { throw Failure.generation("Cannot create image sample.") }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw Failure.generation("Image encoder unavailable: \(resource.label)") }
        case .text:
            try "MenuMate temporary sample\nSecond line for text actions.\n".write(to: url, atomically: true, encoding: .utf8)
        case .sourceCode:
            try "import Foundation\nprint(\"MenuMate sample\")\n".write(to: url, atomically: true, encoding: .utf8)
        case .pdf:
            var box = CGRect(x: 0, y: 0, width: 300, height: 220)
            guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw Failure.generation("Cannot create PDF sample.") }
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(red: 0.2, green: 0.45, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 25, y: 25, width: 250, height: 170))
            context.endPDFPage()
            context.closePDF()
        case .folder:
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try "Temporary folder content.\n".write(to: url.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        case .application:
            let contents = url.appendingPathComponent("Contents", isDirectory: true)
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist: [String: Any] = ["CFBundleIdentifier": "com.menumate.testfixture",
                                       "CFBundleName": "MenuMate Sample", "CFBundlePackageType": "APPL",
                                       "CFBundleVersion": "1"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
        case .archive:
            let payload = url.deletingPathExtension().appendingPathExtension("payload")
            try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: payload) }
            try "Temporary archive content.\n".write(to: payload.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
            let result = ShellRunner.run("/usr/bin/ditto", ["-c", "-k", payload.path, url.path], timeout: 10)
            guard result.exitCode == 0 else { throw Failure.generation(result.stderr) }
        case .audio:
            var bytes = Data()
            func text(_ value: String) { bytes.append(contentsOf: value.utf8) }
            func number<T: FixedWidthInteger>(_ value: T) {
                var little = value.littleEndian
                withUnsafeBytes(of: &little) { bytes.append(contentsOf: $0) }
            }
            let sampleBytes: UInt32 = 16000
            text("RIFF"); number(sampleBytes + 36); text("WAVEfmt "); number(UInt32(16))
            number(UInt16(1)); number(UInt16(1)); number(UInt32(8000)); number(UInt32(16000))
            number(UInt16(2)); number(UInt16(16)); text("data"); number(sampleBytes)
            bytes.append(Data(repeating: 0, count: Int(sampleBytes)))
            try bytes.write(to: url)
        case .video:
            try writeVideo(to: url)
        }
    }

    private static func writeVideo(to url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                                         kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        writer.add(input)
        guard writer.startWriting() else { throw Failure.generation(writer.error?.localizedDescription ?? "Cannot create video sample.") }
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess,
              let buffer else { writer.cancelWriting(); throw Failure.generation("Cannot allocate video sample.") }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 100, CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let deadline = Date().addingTimeInterval(5)
        for frame in 0..<3 {
            while !input.isReadyForMoreMediaData, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
            guard input.isReadyForMoreMediaData,
                  adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 3)) else {
                writer.cancelWriting(); throw Failure.generation(writer.error?.localizedDescription ?? "Cannot encode video sample.")
            }
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        guard done.wait(timeout: .now() + 5) == .success, writer.status == .completed else {
            writer.cancelWriting(); throw Failure.generation(writer.error?.localizedDescription ?? "Video sample timed out.")
        }
    }
}
