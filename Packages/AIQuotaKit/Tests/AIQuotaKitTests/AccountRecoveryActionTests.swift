import Foundation
import Testing
@testable import AIQuotaKit

@Test func accountRecoveryRequiresReconnectForRejectedIdentityEvenWhileAuthenticated() {
    for error in [NetworkError.tokenExpired, .notAuthenticated, .refreshFailed, .accountIdentityMismatch] {
        #expect(AccountRecoveryAction.resolve(authenticated: true, error: error) == .reconnect)
    }
    #expect(AccountRecoveryAction.resolve(authenticated: false, error: nil) == .reconnect)
}

@Test func accountRecoveryOffersReconnectWhenServiceRejectsSavedAccount() {
    for code in [400, 404, 410] {
        #expect(AccountRecoveryAction.resolve(authenticated: true, error: .httpError(statusCode: code)) == .reconnect)
    }
    #expect(AccountRecoveryAction.resolve(authenticated: true, error: .httpError(statusCode: 429)) == .retry)
    // Automatic recovery keeps treating a 404 as non-auth.
    #expect(!NetworkError.httpError(statusCode: 404).needsReconnect)
}

@Test func accountRecoveryKeepsTransientFailuresOnRetryPath() {
    for error in [NetworkError.networkUnavailable, .httpError(statusCode: 503), .rateLimited,
                  .requestFailed, .decodingError(underlying: URLError(.timedOut)), .unknownEndpoint] {
        #expect(AccountRecoveryAction.resolve(authenticated: true, error: error) == .retry)
    }
    // Localized message text is not an authentication signal.
    #expect(AccountRecoveryAction.resolve(authenticated: true, error: nil, hasIssue: true) == .retry)
    #expect(AccountRecoveryAction.resolve(authenticated: true, error: nil) == .none)
}
