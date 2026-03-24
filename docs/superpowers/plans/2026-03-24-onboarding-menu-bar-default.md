# Onboarding Menu Bar Default Picker — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When both Codex and Claude Code are connected during onboarding, show a pair of tap cards that let the user pick which service appears in the menu bar.

**Architecture:** Add a private `MenuBarDefaultPicker` view to `ServicesStepView.swift`. Conditionally render it below the service rows when both services are authenticated, with a spring animation. Each card tap writes directly to `viewModel.settings.menuBarService` and calls `viewModel.saveSettings()` to persist.

**Tech Stack:** SwiftUI, `@Observable` (macOS 14+), `AIQuotaKit.ServiceType`, `AIQuotaKit.AppSettings`

---

## File Map

| Action | File |
|--------|------|
| Modify | `AIQuota/Views/Onboarding/Steps/ServicesStepView.swift` |

No other files touched.

---

## Task 1: Add `MenuBarDefaultPicker` private view

**Files:**
- Modify: `AIQuota/Views/Onboarding/Steps/ServicesStepView.swift`

This task adds the UI component only. No wiring yet — just the view rendering two cards correctly for a given `selection` binding and `onSelect` callback.

- [ ] **Step 1: Add `MenuBarDefaultPicker` struct after the `ServiceRow` struct**

Append this to the bottom of `ServicesStepView.swift` (after line 129, before the final blank line):

```swift
// MARK: - Menu Bar Default Picker

private struct MenuBarDefaultPicker: View {
    let selection: ServiceType
    let onSelect: (ServiceType) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Divider()
                .padding(.horizontal, 32)

            Text("Which should show in your menu bar?")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                card(for: .codex,  logoName: "logo-openai", name: "Codex")
                card(for: .claude, logoName: "logo-claude", name: "Claude Code")
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 16)
    }

    @ViewBuilder
    private func card(for service: ServiceType, logoName: String, name: String) -> some View {
        let isSelected = selection == service
        Button { onSelect(service) } label: {
            VStack(spacing: 10) {
                Image(logoName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(isSelected
                                  ? Color.brand.opacity(0.1)
                                  : Color.secondary.opacity(0.08))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isSelected ? Color.brand.opacity(0.3) : Color.clear,
                                lineWidth: 1.5
                            )
                    )

                Text(name)
                    .font(.callout).fontWeight(.semibold)

                Circle()
                    .strokeBorder(isSelected ? Color.brand : Color.secondary.opacity(0.3),
                                  lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .fill(Color.brand)
                            .frame(width: 8, height: 8)
                            .opacity(isSelected ? 1 : 0)
                    )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.brand.opacity(0.35) : Color.secondary.opacity(0.12),
                                lineWidth: 1
                            )
                    )
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

In Xcode: `Cmd+B` targeting **My Mac**.

Expected: build succeeds. `MenuBarDefaultPicker` is defined but unused — that's fine for now.

---

## Task 2: Wire into `ServicesStepView`

**Files:**
- Modify: `AIQuota/Views/Onboarding/Steps/ServicesStepView.swift` (the `ServicesStepView.body`)

- [ ] **Step 1: Replace the `Spacer()` in `ServicesStepView.body` with a conditional picker + spacer**

Find this block in `ServicesStepView.body` (lines 43–50):

```swift
            Spacer()

            Text("You can connect more services later in Settings.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
```

Replace with:

```swift
            if viewModel.isCodexAuthenticated && viewModel.isClaudeAuthenticated {
                MenuBarDefaultPicker(
                    selection: viewModel.settings.menuBarService,
                    onSelect: { service in
                        viewModel.settings.menuBarService = service
                        viewModel.saveSettings()
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer()

            Text("You can connect more services later in Settings.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
```

Then add an `.animation` modifier to the outer `VStack(spacing: 0)` in `ServicesStepView.body` so the transition fires when auth state changes. The `VStack` closes just before `body`'s closing brace. Add after it:

```swift
        .animation(.spring(response: 0.35, dampingFraction: 0.85),
                   value: viewModel.isCodexAuthenticated && viewModel.isClaudeAuthenticated)
```

- [ ] **Step 2: Build to verify it compiles**

`Cmd+B`. Expected: clean build.

- [ ] **Step 3: Run the app and verify**

Run the `AIQuota` scheme targeting **My Mac**.

Reset onboarding so it shows on launch — in the app, go to **Settings → Reset Onboarding** (or run `viewModel.resetOnboardingForReplay()` in the debugger), then relaunch.

Walk through to the **Services** step:
1. Sign into only one service → picker should **not** appear.
2. Sign into the second service → picker should **animate in** below the service rows.
3. Tap each card → selection indicator moves correctly.
4. Tap **Continue**, then quit and relaunch → open **Settings** and confirm the `menuBarService` matches what was selected.

- [ ] **Step 4: Commit**

```bash
git add AIQuota/Views/Onboarding/Steps/ServicesStepView.swift
git commit -m "feat: show menu bar default picker in onboarding when both services connected"
```
