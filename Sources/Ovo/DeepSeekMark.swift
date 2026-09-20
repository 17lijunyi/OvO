import AppKit
import SwiftUI

/// Official provider mark from https://www.deepseek.com/favicon.ico.
/// The PNG is a lossless format conversion of that public 225 × 225 favicon.
/// DeepSeek's website does not state a separate redistribution license for the mark.
struct DeepSeekMark: View {
    let size: CGFloat

    init(size: CGFloat = 16) {
        self.size = size
    }

    private static let logo: NSImage? = {
        guard let url = Bundle.main.url(forResource: "DeepSeek", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        Group {
            if let logo = Self.logo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color(red: 77 / 255, green: 107 / 255, blue: 254 / 255))
            }
        }
        .padding(size * 0.06)
        .frame(width: size, height: size)
        .background(.white, in: RoundedRectangle(cornerRadius: size * 0.16))
        .accessibilityLabel("DeepSeek")
    }
}
