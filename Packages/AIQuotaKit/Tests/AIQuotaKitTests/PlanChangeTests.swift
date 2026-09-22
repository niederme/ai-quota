import Testing
@testable import AIQuotaKit

@Test func detectsKnownPlanUpgradesAndDowngrades() {
    #expect(PlanChange(previous: "plus", current: "pro")?.current == "Pro")
    #expect(PlanChange(previous: "max", current: "pro")?.previous == "Max")
}

@Test func ignoresMissingPlansFirstSignInAndAliases() {
    #expect(PlanChange(previous: nil, current: "pro") == nil)
    #expect(PlanChange(previous: "pro", current: nil) == nil)
    #expect(PlanChange(previous: "unknown", current: "pro") == nil)
    #expect(PlanChange(previous: "pro", current: "not reported") == nil)
    #expect(PlanChange(previous: " Plus ", current: "plus") == nil)
    #expect(PlanChange(previous: "prolite", current: "Pro") == nil)
}
