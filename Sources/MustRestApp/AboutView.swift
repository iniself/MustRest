import SwiftUI
import AppKit

/// About window content: app name, version and the author's WeChat QR code.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("MustRest")
                .font(.largeTitle.bold())

            Text("版本 \(version)")
                .font(.callout)
                .foregroundColor(.secondary)

            Divider()

            Text("扫码添加作者微信")
                .font(.headline)

            qrImage

            Text("扫一扫上面的二维码图案，加我为朋友。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(width: 420)
    }

    /// Loads the QR code from the target's SwiftPM resource bundle.
    @ViewBuilder
    private var qrImage: some View {
        if let image = Bundle.module.image(forResource: "auiwechat") {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxHeight: 380)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.2))
                )
        } else {
            Text("二维码加载失败")
                .font(.callout)
                .foregroundColor(.red)
        }
    }

    /// Bundle version shown in the About window. The packaging script writes
    /// this key from the version argument (e.g. `./scripts/package.sh 1.2.0`
    /// produces "1.2.0"), so the window always matches the packaged release.
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
