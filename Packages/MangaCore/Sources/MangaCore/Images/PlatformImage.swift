import CoreGraphics
#if canImport(UIKit)
import UIKit
/// `UIImage` on tvOS/iOS, `NSImage` on macOS (where `swift test` runs).
public typealias PlatformImage = UIImage

extension PlatformImage {
    static func make(_ cgImage: CGImage) -> PlatformImage {
        UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
}
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage

extension PlatformImage {
    static func make(_ cgImage: CGImage) -> PlatformImage {
        NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
#endif
