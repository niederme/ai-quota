import XCTest
import SwiftUI
import MobileAccessCore
@testable import AIQuota_iOS

final class TokenHistoryReviewTests: XCTestCase {
    @MainActor func testAnnualGridNarrowLargeLightDark() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let history = try XCTUnwrap(DemoQuotaData.tokenHistory())
        XCTAssertEqual(history.days().count, 364)
        for width in [320.0, 440.0] {
            for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
                let content = NavigationStack {
                    ScrollView {
                        VStack(spacing: 20) {
                            Text("Sample data · iOS layout verification").font(.caption)
                            CodexResetNoticeBanner(announcement: CodexResetNotice.demoAnnouncement, openDetails: {}, dismiss: {}, loading: false)
                            ProviderDialCardContent(name: "Codex", icon: "logo-openai", availableWidth: width - 32,
                                reading: DemoQuotaData.reading(.codex), connected: true, busy: false, error: nil,
                                tokenHistory: history)
                            ProviderDialCardContent(name: "Claude", icon: "logo-claude", availableWidth: width - 32,
                                reading: DemoQuotaData.reading(.claude), connected: true, busy: false, error: nil)
                        }.padding(16)
                    }.background { OverviewBackground().ignoresSafeArea() }
                        .navigationTitle("AIQuota").toolbarTitleDisplayMode(.inlineLarge)
                }.frame(width: width, height: 920).environment(\.colorScheme, scheme)
                let host = UIHostingController(rootView: content)
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: width, height: 920)
                window.rootViewController = host; window.makeKeyAndVisible()
                defer { window.isHidden = true; previous?.makeKey() }
                try await Task.sleep(for: .milliseconds(500))
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: 920))
                let image = renderer.image { _ in host.view.drawHierarchy(in: CGRect(x: 0,y: 0,width: width,height: 920), afterScreenUpdates: true) }
                let path = FileManager.default.temporaryDirectory.appendingPathComponent("ios-token-grid-\(Int(width))-\(name).png")
                try image.pngData()?.write(to: path)
                print("TOKEN_GRID_REVIEW " + path.path)
                XCTAssertEqual(image.size.width, width)
            }
        }
    }
}
