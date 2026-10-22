# Prototypes

Static HTML studies used to settle a design question before it changes the apps.
Each one is self-contained; open `index.html` directly or serve the folder:

```bash
make dev-local SITE_ROOT=prototypes/<name> PORT=8131
```

| Prototype | What it studies | Status |
| --- | --- | --- |
| [`cost-value`](cost-value/README.md) | Language for API-equivalent usage value that does not read as a bill | Exploration |
| [`sheet-material`](sheet-material/README.md) | Tinted purple glass for the Mac menu-bar sheet, judged over white and black desktops | Shipped in [PR #114](https://github.com/niederme/ai-quota/pull/114); tuning continues |

## Design sources

- Figma: [AIQuota](https://www.figma.com/design/cja43k0cJmCFUnGctkDuJ2/AIQuota)
  holds the app icon, splash artwork, and iOS screen explorations.
- Colour values come from the apps' asset catalogs (`iOS/App/Assets.xcassets`
  and `AIQuota/Resources/Assets.xcassets`) and `AIQuota/Views/AdaptiveColors.swift`.
  Treat those files as the source of truth, not the prototypes.
