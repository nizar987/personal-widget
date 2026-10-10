// Renders TaskWidget/Assets.xcassets/AppIcon.appiconset/icon_*.png.
// Usage: swiftc -parse-as-library -target arm64-apple-macos15 scripts/render_app_icon.swift -o /tmp/icon \
//          && /tmp/icon TaskWidget/Assets.xcassets/AppIcon.appiconset
import SwiftUI
import AppKit

private let coral = Color(red: 1.00, green: 0.42, blue: 0.36)
private let amber = Color(red: 1.00, green: 0.76, blue: 0.24)
private let sky = Color(red: 0.37, green: 0.62, blue: 1.00)
private let green = Color(red: 0.30, green: 0.82, blue: 0.48)

/// 1024×1024 macOS icon: 824pt squircle on a transparent canvas (Apple icon grid).
struct IconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 186, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.21, blue: 0.28),
                                              Color(red: 0.07, green: 0.07, blue: 0.10)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 186, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 5)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.45), radius: 24, y: 14)

            // Inner LockDay-style tile
            RoundedRectangle(cornerRadius: 96, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .frame(width: 640, height: 600)

            VStack(alignment: .leading, spacing: 62) {
                row(done: true, color: green, width: 300)
                row(done: false, color: coral, width: 360)
                row(done: false, color: amber, width: 250)
            }
            .offset(x: -4)
        }
        .frame(width: 1024, height: 1024)
    }

    private func row(done: Bool, color: Color, width: CGFloat) -> some View {
        HStack(spacing: 46) {
            ZStack {
                if done {
                    Circle().fill(color)
                    Image(systemName: "checkmark")
                        .font(.system(size: 58, weight: .black))
                        .foregroundStyle(.white)
                } else {
                    Circle().strokeBorder(color, lineWidth: 24)
                }
            }
            .frame(width: 104, height: 104)
            Capsule()
                .fill(Color.white.opacity(done ? 0.30 : 0.92))
                .frame(width: width, height: 42)
        }
    }
}

@main struct R {
    @MainActor static func main() {
        let out = CommandLine.arguments[1]
        let renderer = ImageRenderer(content: IconView())
        renderer.scale = 1
        guard let master = renderer.cgImage else { fatalError("render failed") }
        let sizes: [(String, Int)] = [
            ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
            ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
            ("512x512", 512), ("512x512@2x", 1024),
        ]
        for (name, px) in sizes {
            let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .high
            ctx.draw(master, in: CGRect(x: 0, y: 0, width: px, height: px))
            let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
            try! rep.representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
        }
        print("ok")
    }
}
