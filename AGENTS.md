# Agent Guide (macOS / SwiftUI)

This project is a native macOS menubar app built with SwiftUI. It shows the user's GitHub notifications in the menubar.

## Project stance

- This is a small utility. Keep everything simple; no over-engineering.
- Support only the latest 3 macOS versions. The latest is macOS 26 (so support 24/25/26).

## Principles (keep it simple)

- Prefer system frameworks: SwiftUI / Foundation / Swift Concurrency (when needed).
- Avoid third-party dependencies unless clearly necessary; state the reason and alternatives.
- Avoid heavy architecture/abstractions (no premature layers, protocols-for-everything, DI containers, etc.).
- Optimize for readability and low maintenance.

## Swift / Concurrency

- Swift 6.2+, strict concurrency; shared state uses `@Observable` and is `@MainActor`.
- No legacy GCD. Use `await MainActor.run {}` or `@MainActor` semantics instead of `DispatchQueue.main.async()`.
- Avoid force unwraps and force `try` unless truly unrecoverable.
- Prefer modern Foundation APIs (e.g. `URL.documentsDirectory`, `appending(path:)`, `replacing(_:with:)`).

## SwiftUI

- Use `foregroundStyle()`; use `clipShape(.rect(cornerRadius:))` for rounding.
- Prefer `Button`; avoid `onTapGesture()` unless you need tap details.
- Use the new `Tab` API; navigation via `NavigationStack` + `navigationDestination(for:)`.
- Don’t use 1-parameter `onChange`; use `Task.sleep(for:)`.
- Filter user input with `localizedStandardContains()`.

## Compatibility

- Target macOS 24/25/26; gate newer APIs with `@available` or conditional fallbacks.
- Menubar UX follows HIG: lightweight, fast to open, low distraction.
