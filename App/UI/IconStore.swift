// IconStore.swift — 用户导入的自定义动作图标的导入 / 缩放 / 存储 / 取用。
//
// 自定义图片存到 AppPaths.iconsDirectory()（= 配置目录/Icons/，非受保护区，主 App 读写）。
// Finder 扩展零文件访问，故菜单渲染靠快照携带的 base64(PNG) 字节，不从此目录读。
// 导入时统一缩放到 36×36（保持纵横比、居中 fit、透明背景）再编码 PNG，控制快照体积。

import Foundation
import AppKit
import MenuMateCore

enum IconStore {
    /// 导入后落盘的图标边长（px）。36 足够 App 内 36pt 头部清晰，且 PNG 字节小（~1–4KB）。
    private static let targetSize: CGFloat = 36

    /// 从源图片文件导入：读取 → 缩放到 36×36（fit + 透明背景）→ PNG → 写入 Icons/<uuid>.png。
    /// 成功返回相对文件名（如 "A1B2-….png"），失败返回 nil。
    static func importImage(from src: URL) -> String? {
        guard let source = NSImage(contentsOf: src),
              let png = scaledPNG(source) else { return nil }
        let dir = AppPaths.iconsDirectory()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch { return nil }
        let fileName = "\(UUID().uuidString).png"
        let dest = dir.appendingPathComponent(fileName)
        do {
            try png.write(to: dest)
        } catch { return nil }
        return fileName
    }

    /// 图标文件的绝对 URL。
    static func imageURL(for fileName: String) -> URL {
        AppPaths.iconsDirectory().appendingPathComponent(fileName)
    }

    /// 读盘加载为 NSImage（供 App 内预览渲染），缺失返回 nil。
    static func loadNSImage(_ fileName: String) -> NSImage? {
        let url = imageURL(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    /// 读取图标 PNG 字节并 base64（供快照传给扩展），缺失返回 nil。
    static func base64PNG(for fileName: String) -> String? {
        let url = imageURL(for: fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return data.base64EncodedString()
    }

    /// 删除图标文件（单文件清理用）。
    static func remove(_ fileName: String) {
        try? FileManager.default.removeItem(at: imageURL(for: fileName))
    }

    /// 垃圾回收：删除 Icons/ 下未被任何动作引用的 .png（孤儿）。
    /// `referenced` = 当前 config 仍在用的图标文件名集合。一并覆盖动作删除、
    /// 图标更换、导入后中途放弃等所有产生孤儿的路径，比逐处 hook 删除点更稳。
    static func pruneOrphans(keeping referenced: Set<String>) {
        let dir = AppPaths.iconsDirectory()
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension.lowercased() == "png" {
            if !referenced.contains(url.lastPathComponent) {
                try? fm.removeItem(at: url)
            }
        }
    }

    /// 把任意 NSImage 缩放到 targetSize 见方（保持纵横比、居中、透明背景），返回 PNG 数据。
    private static func scaledPNG(_ image: NSImage) -> Data? {
        let side = Int(targetSize)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: targetSize, height: targetSize)

        // 源尺寸：优先用位图像素尺寸，回退到 NSImage.size。
        let srcSize = pixelSize(of: image)
        guard srcSize.width > 0, srcSize.height > 0 else { return nil }
        let scale = min(targetSize / srcSize.width, targetSize / srcSize.height)
        let drawW = srcSize.width * scale
        let drawH = srcSize.height * scale
        let drawRect = NSRect(x: (targetSize - drawW) / 2, y: (targetSize - drawH) / 2,
                              width: drawW, height: drawH)

        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        NSColor.clear.set()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: targetSize, height: targetSize))
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    /// 取源图片的像素尺寸（优先位图 rep 的真实像素，避免 NSImage.size 受 DPI 影响失真）。
    private static func pixelSize(of image: NSImage) -> NSSize {
        for rep in image.representations {
            if rep.pixelsWide > 0, rep.pixelsHigh > 0 {
                return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
            }
        }
        return image.size
    }
}
