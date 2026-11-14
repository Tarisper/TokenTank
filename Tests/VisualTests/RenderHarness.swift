import AppKit
import SwiftUI

/// PNG rendering and reference comparison (REQ-UI-15). References are generated
/// locally (`VISUAL_TESTS_GENERATE=1`) and are not committed (M3.2 policy).
enum RenderHarness {
    static var isGenerateMode: Bool {
        ProcessInfo.processInfo.environment["VISUAL_TESTS_GENERATE"] == "1"
    }

    static var referenceDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Reference")
    }

    /// Deterministic wallpapers replacing binary fixtures: solid white, solid
    /// dark and a colorful procedural image (§8.4).
    enum Wallpaper: String {
        case white
        case dark
        case colorful

        @MainActor
        func image(size: CGSize) -> CGImage {
            let context = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            switch self {
            case .white:
                context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                context.fill(CGRect(origin: .zero, size: size))
            case .dark:
                context.setFillColor(CGColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1))
                context.fill(CGRect(origin: .zero, size: size))
            case .colorful:
                for x in 0..<Int(size.width) {
                    for y in 0..<Int(size.height) {
                        let r = CGFloat((x * 73 + y * 151) % 255) / 255
                        let g = CGFloat((x * 29 + y * 97) % 255) / 255
                        let b = CGFloat((x * 199 + y * 13) % 255) / 255
                        context.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
                        context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                    }
                }
            }
            return context.makeImage()!
        }
    }

    /// Renders the content over a wallpaper with a material panel (as on the desktop).
    @MainActor
    static func render<V: View>(view: V, wallpaper: Wallpaper, colorScheme: ColorScheme, size: CGSize) -> Data {
        let content = view
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.regularMaterial)
            )
            .environment(\.colorScheme, colorScheme)
        let composed = ZStack {
            Image(decorative: wallpaper.image(size: size), scale: 1)
                .resizable()
                .frame(width: size.width, height: size.height)
            content
        }
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: composed)
        renderer.scale = 2
        let image = renderer.cgImage!
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])!
    }

    /// Verifies a render against the generated reference (or writes it).
    @MainActor
    static func verify(name: String, view: some View, wallpaper: Wallpaper, colorScheme: ColorScheme, size: CGSize) throws {
        let data = render(view: view, wallpaper: wallpaper, colorScheme: colorScheme, size: size)
        let referenceURL = referenceDir.appendingPathComponent("\(name).png")
        if isGenerateMode {
            try FileManager.default.createDirectory(at: referenceDir, withIntermediateDirectories: true)
            try data.write(to: referenceURL)
            return
        }
        guard FileManager.default.fileExists(atPath: referenceURL.path) else {
            throw RenderError.missingReference(name)
        }
        let expected = try Data(contentsOf: referenceURL)
        try compare(expected: expected, actual: data, name: name)
    }

    /// Pixel comparison with a small per-channel tolerance (font antialiasing).
    static func compare(expected: Data, actual: Data, name: String) throws {
        guard
            let expectedRep = NSBitmapImageRep(data: expected),
            let actualRep = NSBitmapImageRep(data: actual),
            expectedRep.pixelsWide == actualRep.pixelsWide,
            expectedRep.pixelsHigh == actualRep.pixelsHigh
        else {
            throw RenderError.mismatch(name)
        }
        let tolerance = 3
        var differing = 0
        let total = expectedRep.pixelsWide * expectedRep.pixelsHigh
        for y in 0..<expectedRep.pixelsHigh {
            for x in 0..<expectedRep.pixelsWide {
                guard
                    let e = expectedRep.colorAt(x: x, y: y),
                    let a = actualRep.colorAt(x: x, y: y)
                else {
                    differing += 1
                    continue
                }
                let channelDelta = abs(e.redComponent - a.redComponent) * 255
                    + abs(e.greenComponent - a.greenComponent) * 255
                    + abs(e.blueComponent - a.blueComponent) * 255
                if channelDelta > Double(tolerance * 3) {
                    differing += 1
                }
            }
        }
        if Double(differing) > Double(total) * 0.005 {
            throw RenderError.mismatch(name)
        }
    }
}

enum RenderError: Error {
    case missingReference(String)
    case mismatch(String)
}
