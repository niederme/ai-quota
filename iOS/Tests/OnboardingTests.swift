import XCTest
import SwiftUI
@testable import AIQuota_iOS

@MainActor
final class OnboardingTests: XCTestCase {
    private func isolated(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "onboarding-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
    func testFreshInstallStartsAndInterruptedPartialSetupResumes() throws {
        try isolated { defaults in
            let progress = OnboardingProgress(defaults: defaults)
            XCTAssertTrue(progress.shouldPresent(hasExistingAccount: false))
            XCTAssertEqual(progress.step, .welcome)
            progress.setStep(.services)
            // A successful first connection during setup must not suppress the remaining steps.
            let reopened = OnboardingProgress(defaults: defaults)
            XCTAssertTrue(reopened.shouldPresent(hasExistingAccount: true))
            XCTAssertEqual(reopened.step, .services)
        }
    }
    func testUpgradeWithExistingAccountDoesNotForceSetup() throws {
        try isolated { defaults in
            let progress = OnboardingProgress(defaults: defaults)
            XCTAssertFalse(progress.shouldPresent(hasExistingAccount: true, hasExistingInstallation: true))
            XCTAssertFalse(OnboardingProgress(defaults: defaults).shouldPresent(hasExistingAccount: false))
            progress.begin()
            XCTAssertEqual(progress.step, .welcome)
            XCTAssertTrue(progress.shouldPresent(hasExistingAccount: true))
        }
    }
    func testSkippedAndFailedSignInCanResumeWithoutLosingProgress() throws {
        try isolated { defaults in
            let progress = OnboardingProgress(defaults: defaults)
            XCTAssertTrue(progress.shouldPresent(hasExistingAccount: false))
            progress.setStep(.services)
            // Failed sign-in creates no account; skip still prevents repeated automatic setup.
            progress.dismiss()
            let reopened = OnboardingProgress(defaults: defaults)
            XCTAssertFalse(reopened.shouldPresent(hasExistingAccount: false))
            reopened.begin()
            XCTAssertEqual(reopened.step, .services)
            XCTAssertTrue(reopened.shouldPresent(hasExistingAccount: false))
        }
    }
    func testCompletionWithoutAccountsAndReplay() throws {
        try isolated { defaults in
            let progress = OnboardingProgress(defaults: defaults)
            progress.begin()
            progress.setStep(.widgets)
            progress.finish()
            let reopened = OnboardingProgress(defaults: defaults)
            XCTAssertTrue(reopened.completed)
            XCTAssertFalse(reopened.shouldPresent(hasExistingAccount: false))
            reopened.begin()
            XCTAssertEqual(reopened.step, .welcome)
            // Reviewing setup must not erase its previous completion.
            reopened.dismiss()
            XCTAssertFalse(OnboardingProgress(defaults: defaults).shouldPresent(hasExistingAccount: true))
        }
    }
    func testReinstallWithRetainedCredentialsStillShowsWelcome() throws {
        try isolated { defaults in
            let progress = OnboardingProgress(defaults: defaults)
            XCTAssertTrue(progress.shouldPresent(hasExistingAccount: true, hasExistingInstallation: false))
            XCTAssertEqual(progress.step, .welcome)
            // Retained credentials are not cleared by presenting or completing setup.
            progress.finish()
            XCTAssertFalse(OnboardingProgress(defaults: defaults).shouldPresent(hasExistingAccount: true))
        }
    }
    func testGuidedSetupAlwaysStartsAtWelcomeAndPreservesSettings() throws {
        try isolated { defaults in
            defaults.set(10, forKey: "refreshIntervalMinutes")
            let progress = OnboardingProgress(defaults: defaults)
            progress.setStep(.notifications)
            progress.dismiss()
            progress.replay()
            XCTAssertEqual(progress.step, .welcome)
            XCTAssertEqual(defaults.integer(forKey: "refreshIntervalMinutes"), 10)
            XCTAssertTrue(progress.shouldPresent(hasExistingAccount: true))
        }
    }
    func testResetClearsOnlyOwnedPreferencesAndReturnsToFirstRun() throws {
        try isolated { defaults in
            defaults.set("keep", forKey: "unrelated")
            defaults.set(10, forKey: "refreshIntervalMinutes")
            defaults.set(true, forKey: "notifications.enabled")
            defaults.set(false, forKey: "notifications.claude")
            let progress = OnboardingProgress(defaults: defaults)
            progress.finish()
            MobileSettingsReset.clearPreferences(standard: defaults, shared: defaults)
            progress.reset()
            XCTAssertFalse(progress.completed)
            XCTAssertEqual(progress.step, .welcome)
            XCTAssertTrue(progress.shouldPresent(hasExistingAccount: false))
            XCTAssertNil(defaults.object(forKey: "refreshIntervalMinutes"))
            XCTAssertNil(defaults.object(forKey: "notifications.enabled"))
            XCTAssertNil(defaults.object(forKey: "notifications.claude"))
            XCTAssertEqual(defaults.string(forKey: "unrelated"), "keep")
        }
    }
    func testOldWidgetStepSurvivesAddedNotificationsAndCompletion() throws {
        try isolated { defaults in
            defaults.set(2, forKey: "onboarding.v1.step")
            XCTAssertEqual(OnboardingProgress(defaults: defaults).step, .widgets)
            XCTAssertEqual(OnboardingProgress.order, [.welcome, .services, .notifications, .widgets, .complete])
        }
    }
    func testInvalidSavedStepFallsBackSafely() throws {
        try isolated { defaults in
            defaults.set(99, forKey: "onboarding.v1.step")
            XCTAssertEqual(OnboardingProgress(defaults: defaults).step, .welcome)
        }
    }
    func testOnboardingRenderAtLargeTextAndNarrowWidth() throws {
        for dark in [false, true] {
            let content = VStack(alignment: .leading, spacing: 32) {
                OnboardingWelcome()
                Divider()
                LockScreenSetupContent()
            }.padding(24).frame(width: 320)
                .background(OverviewStyle.base)
                .foregroundStyle(OverviewStyle.primary)
                .tint(OverviewStyle.accent)
                .environment(\.colorScheme, dark ? .dark : .light)
                .environment(\.dynamicTypeSize, .accessibility1)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = dark ? "Onboarding dark large text" : "Onboarding light large text"
            attachment.lifetime = .keepAlways
            add(attachment)
            let path = FileManager.default.temporaryDirectory.appendingPathComponent(dark ? "onboarding-dark.png" : "onboarding-light.png")
            try image.pngData()?.write(to: path)
            print("ONBOARDING_REVIEW " + path.path)
        }
    }
}

import MobileAccessCore
private struct RejectedCodeTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> HTTPResult {
        HTTPResult(data: Data(#"{"error":"invalid_grant"}"#.utf8), status: 400)
    }
}
@MainActor final class ClaudeSignInStateTests: XCTestCase {
    func testClaudeResetReturnsToFreshSetupState() async throws {
        let id = UUID().uuidString
        let store = SharedQuotaStore(.claude, root: FileManager.default.temporaryDirectory.appendingPathComponent(id), namespace: id)
        let model = ClaudeProbeModel(shared: store, restore: false)
        model.connect()
        XCTAssertNotNil(model.challenge)
        try await model.resetForNewUser()
        XCTAssertEqual(model.message, "Connect Claude to see your usage.")
        XCTAssertNil(model.challenge)
        XCTAssertNil(model.signInCompletionID)
        XCTAssertNil(model.connectionFailure)
        XCTAssertNil(model.error)
        XCTAssertFalse(model.connected)
        XCTAssertFalse(model.busy)
        if let root = store.root { try? FileManager.default.removeItem(at: root) }
    }

    func testFailedCodeSubmissionKeepsAttemptForCorrection() async throws {
        let id = UUID().uuidString
        let store = SharedQuotaStore(.claude, root: FileManager.default.temporaryDirectory.appendingPathComponent(id), namespace: id)
        let model = ClaudeProbeModel(api: ClaudeAPI(transport: RejectedCodeTransport()), shared: store, restore: false)
        model.connect()
        let state = try XCTUnwrap(model.challenge?.state)
        model.finishSignIn("incorrect")
        for _ in 0..<100 where model.busy { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(model.challenge?.state, state)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.connected)
        model.finishSignIn("synthetic#" + state)
        for _ in 0..<100 where model.busy { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(model.challenge?.state, state)
        XCTAssertNotNil(model.error)
        model.cancel()
        XCTAssertNil(model.challenge)
    }
}
