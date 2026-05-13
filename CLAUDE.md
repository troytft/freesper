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

- **No comments by default.** The bar for writing a comment is very
  high. Code must explain itself through naming, types, and structure.
  If a name or signature isn't clear — improve the name, don't add a
  comment.

- **Do not write** comments that:
  - describe WHAT the code does (a well-named function or variable
    already does that);
  - reference the current task, fix, PR, or issue ("added for X",
    "fixes #123", "used by Y", "handles the case from …");
  - restate framework or language behavior that can be looked up in
    the documentation;
  - mark removed code (`// removed X`, commented-out blocks) or
    TODO/FIXME without concrete context.

- **A comment is allowed only** when the WHY is genuinely non-obvious
  and the next reader would otherwise break the code or waste
  significant time: a hidden invariant, a specific framework gotcha
  that already bit us, a counterintuitive workaround with the reason.
  One short line.

- **If in doubt — don't write it.**

## Folders

- **A folder must represent a clear concept** — a domain, feature,
  screen, or a coherent group of related things. Before creating
  one, be able to say in one sentence what concept it represents.

- **Single-file folders are fine when intentional.** If this is the
  first file of a group you can already name (you know the next 2–3
  files that will join it shortly) — create the folder. If you're
  just giving one file a "home" because it felt lonely — don't.

- **Match the existing structure.** Before inventing new
  organization, look at how the surrounding code is organized and
  follow that pattern.

- **If you can't explain what the folder is for — don't create it.**
  Flat next to similar files is the default.
