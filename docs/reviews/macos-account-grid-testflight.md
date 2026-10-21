# macOS account grid TestFlight check

This internal macOS beta keeps the existing combined menu-bar gauge treatment. The open panel uses two columns when 600 points of width are available and one column on narrower displays. With odd account counts, the last card stays on the left. The viewport scrolls when the available screen height cannot show every row.

## Test on a Mac

1. Connect one through six accounts using distinct names, including a long name. In Settings, add accounts by naming them before sign-in. Check that every card remains inside the panel and that its plan, usage, reset, loading, and error text remain readable.
2. Reorder accounts by dragging, the card context menu, and VoiceOver's Move earlier/later actions. Close and reopen the panel; verify the order persists. For three and five accounts, confirm the final card stays in the left column.
3. Resize display resolution or use a smaller laptop screen. Confirm that the panel fits the available width and shows a scroll bar only if rows exceed the available height. Open and close account detail repeatedly while usage refreshes; watch for jumps or clipped Settings/Quit controls.
4. In onboarding, select the accounts for the menu bar. Up to two should be selected initially. In Settings, select three or more, clear all selections, and reconnect or add an account. The single combined menu-bar item should show the selected gauges, or the app icon for an empty selection. New accounts should not be automatically selected after an explicit choice; panel reordering should not change this list.
5. Add a small or single-service medium widget, choose a specific account in widget configuration, and compare its values with the matching panel card. Changing the menu-bar selection must not change the widget's account. Existing service-only widget configurations should continue to work.

The static comparison widgets and service-level alerts still use the original provider connections. Additional account detail has summary metrics, not the complete historical analytics of the original provider detail. Live multi-account browser sign-in and sandboxed widget refresh need hands-on TestFlight verification.
