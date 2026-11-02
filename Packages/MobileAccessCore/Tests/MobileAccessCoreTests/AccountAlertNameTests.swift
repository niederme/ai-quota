import Testing
@testable import MobileAccessCore

@Test func alertNamesSuppressOnlyUnclaimedOrdinalLabels() {
    for service in ["Codex", "Claude"] {
        for label in ["Account 1", "Account 2", " Service 12 ", "account\t3", ""] {
            #expect(AccountAlertName.make(service: service, label: label) == service)
        }
        #expect(AccountAlertName.make(service: service, label: "Account 2", explicitlyNamed: true)
                == "\(service) · Account 2")
        for label in ["Work", "Personal", "Account Research", "Service Desk", "Account 2 West"] {
            #expect(AccountAlertName.make(service: service, label: label) == "\(service) · \(label)")
        }
        #expect(AccountAlertName.make(service: service, label: " \(service) Pro ") == "\(service) Pro")
        #expect(AccountAlertName.make(service: service, label: service.lowercased()) == service.lowercased())
    }
}
