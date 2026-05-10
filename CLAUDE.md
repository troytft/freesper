# Conventions

## Dependency wiring

- **No singletons.** Never use `static let shared`. Services are plain
  classes or actors with an `init(...)`.
- **Composition root.** The dependency graph is built exactly once in
  `FreesperApp.init()` (or in a `bootstrap()` it calls).
- **Init injection.** Each service receives its dependencies as
  initializer parameters. Never reach for globals from inside methods.
- **No DI containers.** Do not pull in `swift-dependencies`, `Swinject`,
  `Factory`, or similar. Manual wiring in one place.
- **SwiftUI views** receive `@Observable` models via `.environment(...)`
  or as initializer parameters — same rule, no globals.

## Comments

- **Default to no comment.** Don't restate what names and signatures
  already say. Write a comment only when the WHY is non-obvious — a
  framework gotcha, magic-number rationale, a workaround, a surprising
  invariant. If removing it wouldn't confuse a future reader, don't
  write it.
