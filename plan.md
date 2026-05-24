# Onboarding redesign

## Why

The current `SetupView` is a single page showing three permission/model rows
in parallel with a quiet checklist. It works but it doesn't explain what
Freesper is, doesn't let the user pick their hotkey, and doesn't let them
feel the product before they're dumped into "you're set". The user lands
without context, fixes whatever the chrome tells them to fix, and the
window closes itself.

We're replacing it with a linear stepper — one concept per screen, the
user clicks **Continue** between steps, presses **Finish** at the end.
The window only closes on Finish (or on explicit user close), never
auto-dismisses on readiness.

## Steps

Six steps, in order:

1. **Welcome** — descriptive copy explaining what Freesper is and how it
   works at a high level. Not an instruction list. Something like:

   > Freesper turns what you say into text. It lives in your menu bar —
   > press a hotkey, speak, your words land in whatever app you're using.
   > Everything runs on your Mac.

   Single primary button: **Continue**.

2. **Microphone** — short copy on why it's needed (recorded only while
   hotkey is held). Primary action triggers the system prompt directly
   via `MicrophonePermission.request()`. If status is `.denied`, swap to
   **Open System Settings** + secondary text "Toggle Freesper in the
   list, then come back." Big green checkmark + status text once granted.
   **Continue** unlocks when `mic == .granted`.

3. **Accessibility** — copy on why it's needed (to paste into the focused
   app). Primary action: **Open System Settings** (calls
   `SystemSettings.open(.accessibility)`). Live state: "Waiting for
   permission…" flips to "Granted ✓" via the existing
   `didBecomeActiveNotification` → `readiness.refreshPermissions()`
   wiring. **Continue** unlocks when `accessibility == .granted`.

4. **Speech model** — copy: "≈600 MB, downloads once, stays on your
   Mac." Full-width progress bar. If `.failed`, show the error + **Retry**
   button (calls `modelManager.retry()`). **Continue** unlocks when
   `model.isReady`.

5. **Hotkey** — short copy. Two pickers bound to `preferences`:
   - Hotkey preset (`HotkeyPreset.allCases`)
   - Mode (Hold / Toggle, segmented)

   **Continue** is always enabled (defaults are valid).

6. **Try it** — copy: "Press and hold your hotkey, say something." A
   focused, multi-line, read-only-feeling `TextField` (or `TextEditor`)
   in the center. The user holds the real hotkey; the existing
   dictation pipeline records → transcribes → pastes via `PasteService`.
   Because the onboarding window is key and the field is first responder,
   the paste lands in that field — no special wiring.

   Show a "Got it ✓" affordance once a transcript has been delivered
   during this step (observe `lastTranscriptStore.text` changing from
   its snapshot taken on step entry).

   **Finish** is always enabled — Try It is skippable. Pressing it
   persists `hasCompletedOnboarding = true` and dismisses the window.

### Step-to-step navigation

- **Back** is available on every step except Welcome.
- **Continue** is the primary, right-aligned action.
- No auto-advance. The user always clicks Continue themselves; the green
  ✓ on permission steps is celebration, not a trigger.
- A horizontal progress strip (six small pills) sits at the top of the
  window showing current position. Not interactive.

### Snap-back on readiness loss

If the user is past a step whose precondition just broke (e.g., on
Hotkey when accessibility gets revoked), the coordinator snaps
`currentStep` back to the first not-satisfied step. Computed as:

```
let order: [Step] = [.welcome, .microphone, .accessibility, .model, .hotkey, .tryIt]
let firstBroken = order.first { !$0.isSatisfied(readiness) }
if let firstBroken, order.firstIndex(of: currentStep)! > order.firstIndex(of: firstBroken)! {
  currentStep = firstBroken
}
```

`welcome` and `hotkey` and `tryIt` are always satisfied for snap-back
purposes (they have no readiness precondition).

## Window

- SwiftUI `Window(id: OnboardingWindow.id)`, single instance.
- Fixed size **580 × 520**, `.windowResizability(.contentSize)`.
- Standard title bar with title "Welcome to Freesper" (or just
  "Freesper"). No custom chrome.
- Acquires `.onboarding` reason on `ActivationPolicyController` while
  visible (rename existing `.setup` reason to `.onboarding`).

### Show / hide rules

Persistent flag: `hasCompletedOnboarding: Bool` in `UserDefaults`
(added to `Preferences` next to the other booleans, key
`preferences.hasCompletedOnboarding`).

On launch, after `bootstrap()`:

| `hasCompletedOnboarding` | `readiness.isReady` | Action                                |
|--------------------------|---------------------|---------------------------------------|
| false                    | (any)               | Open at `.welcome`                    |
| true                     | false               | Open at first not-satisfied step (skip Welcome) |
| true                     | true                | Don't open                            |

At runtime, whenever `readiness.isReady` flips from true → false:
- if the window is closed → open it at first not-satisfied step
- if the window is open → run snap-back

`readiness.isReady` flipping to true while onboarding is open does **not**
auto-close the window. The user must press Finish.

The window closing without Finish (user hits red close button) does
**not** flip `hasCompletedOnboarding`. Next launch / next readiness
drop will reopen the flow.

## Menu bar

Two states, driven by `hasCompletedOnboarding`:

**Pre-completion** — minimal:
- Continue Setup…  → opens onboarding window, brings to front
- About            → opens main window on About tab
- ─
- Quit

**Post-completion** — current full menu:
- Copy last transcript (disabled if none)
- ─
- Settings…
- About
- ─
- Quit

The menu rebuild happens automatically because SwiftUI's `MenuBarExtra`
content is a view tree — branching on
`graph.preferences.hasCompletedOnboarding` re-renders when the
preference flips.

`AppDelegate.onReopen` (dock-icon click when app already running):
- If `!hasCompletedOnboarding || !readiness.isReady` → open onboarding
- Else → open main window on Settings

## Architecture

### New types

```
Sources/Freesper/Onboarding/
  OnboardingWindow.swift          // enum holding the window id
  OnboardingStep.swift            // enum + isSatisfied(readiness)
  OnboardingCoordinator.swift     // @MainActor @Observable, replaces SetupCoordinator
  OnboardingView.swift            // window root: progress strip + current step + nav row
  OnboardingStepChrome.swift      // shared layout (icon, title, body, action slot, status slot)
  Steps/
    WelcomeStep.swift
    MicrophoneStep.swift
    AccessibilityStep.swift
    ModelStep.swift
    HotkeyStep.swift
    TryItStep.swift
```

### `OnboardingStep`

```swift
enum OnboardingStep: Int, CaseIterable {
  case welcome, microphone, accessibility, model, hotkey, tryIt

  func isSatisfied(_ readiness: AppReadiness) -> Bool {
    switch self {
    case .welcome, .hotkey, .tryIt: return true
    case .microphone: return readiness.mic == .granted
    case .accessibility: return readiness.accessibility == .granted
    case .model: return readiness.model.isReady
    }
  }
}
```

### `OnboardingCoordinator`

Mirrors the shape of `SetupCoordinator`:

- `@Observable`, `@MainActor`, holds `currentStep`, exposes
  `openWindow` / `dismissWindow` closures wired from the menu bar view.
- Init dependencies: `readiness`, `preferences` (for the persistence
  flag and for hotkey pickers), `overlay`, `activationPolicy`.
- `start()` performs initial open decision and arms the readiness
  observer.
- `continueFromCurrentStep()` advances `currentStep` if not on last
  step.
- `back()` decrements.
- `finish()` sets `preferences.hasCompletedOnboarding = true` and
  dismisses.
- `openFromMenu()` opens at the right step using the same launch
  decision table.

The readiness observer:
- runs snap-back if window is open
- opens window (at first not-satisfied) if window is closed and
  `!isReady`
- does nothing when `isReady` becomes true (Finish is user-driven)

### `OnboardingView`

Layout:

```
┌────────────────────────────────────┐
│ ●●●○○○                             │  progress strip
│                                    │
│        (step content — chrome)     │
│                                    │
│ [Back]                  [Continue] │  nav row (Finish on last step)
└────────────────────────────────────┘
```

The current step view is rendered via a switch on `coordinator.currentStep`.
Each step view receives only what it needs (`readiness`, `modelManager`,
`preferences`, etc.) via init — no environment lookup.

### `OnboardingStepChrome`

A `ViewBuilder`-based container that all step views render inside.
Provides consistent spacing for: large SF Symbol at top, title, body
text, and an "action slot" + "status slot" the step fills in. Keeps the
six step files small.

### Try It wiring

- `TryItStep` keeps a `@State var draft: String = ""` bound to a
  `TextEditor` with `.focused($isFocused)` set on appear.
- On appear, snapshots `lastTranscriptStore.text` → `baseline`.
- Observes `lastTranscriptStore.text`; when it differs from `baseline`
  and is non-nil, flips a local `didDictate = true` and shows the
  "Got it ✓" affordance under the editor.
- Whether `didDictate` is true or not, the bottom nav's Finish button
  is always enabled — this is purely a visual confirmation.

No changes needed to `DictationCoordinator` or `PasteService`. The
existing pipeline pastes into the focused field, which will be the
`TextEditor` inside our window.

### `Preferences` change

Add:

```swift
var hasCompletedOnboarding: Bool {
  didSet {
    guard oldValue != hasCompletedOnboarding else { return }
    defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
  }
}
```

with corresponding init and `Keys.hasCompletedOnboarding =
"preferences.hasCompletedOnboarding"`.

### `AppGraph` change

Replace:

```swift
let setupCoordinator: SetupCoordinator
```

with:

```swift
let onboardingCoordinator: OnboardingCoordinator
```

and update the init wiring. Pass `preferences` into the coordinator
along with the existing deps.

### `FreesperApp` changes

1. Replace the `Setup` `Window` scene with an `Onboarding` `Window`
   scene pointing at `OnboardingWindow.id` and `OnboardingView`.
2. Make the `MenuBarExtra` content branch on
   `graph.preferences.hasCompletedOnboarding` and render the two
   different menus described above.
3. Rewire `MenuBarLabel.onAppear` closures to
   `graph.onboardingCoordinator.openWindow` /
   `dismissWindow`.
4. Update `appDelegate.onReopen` to follow the new dock-reopen rule.

### `ActivationPolicyController` rename

`Reason.setup` → `Reason.onboarding`. Single mechanical rename.

## Files to delete

- `Sources/Freesper/Setup/SetupCoordinator.swift`
- `Sources/Freesper/Setup/SetupView.swift`
- `Sources/Freesper/Setup/SetupWindow.swift`
- (the empty `Setup/` directory)

If `Project.swift` lists sources explicitly rather than globbing, update
it. Tuist projects usually glob — check before assuming.

## Out of scope / deferred

- **Window focus / activation bugs.** Do not pre-fix. Build the new
  flow, then verify by running the app. If the onboarding window
  doesn't come forward on first launch / on readiness drop, debug
  the root cause then — don't paper over it with
  `DispatchQueue.main.async` or sleep hacks.
- **Localization.** All copy in English, same as the rest of the app.
- **Animations between steps.** A plain swap is fine. Can be added
  later.
- **Icons / illustrations.** Use SF Symbols (`mic.fill`,
  `accessibility`, `arrow.down.circle`, `keyboard`, `waveform`,
  `hand.wave.fill`). No custom assets needed.

## Verification checklist

After implementation, manually verify:

- Fresh install (delete `hasCompletedOnboarding` from defaults):
  onboarding opens at Welcome.
- Walk through all six steps, granting permissions and downloading
  the model. Finish closes the window.
- Relaunch app: window does not open. Menu bar shows full menu.
- Revoke Microphone in System Settings → return to Freesper:
  onboarding reopens at Microphone, menu bar reverts to minimal.
- Open onboarding via "Continue Setup…" from the menu, close it with
  the red button without finishing: relaunch shows it again.
- On Try It, press the hotkey and dictate: text appears in the
  TextEditor, "Got it ✓" appears under it.
- Dock icon click while onboarding incomplete opens onboarding;
  while complete and ready opens Settings.
