import CoreGraphics

struct Hotkey: Equatable, @unchecked Sendable {
  /// `nil` means "bare modifier hotkey" — match a flagsChanged transition.
  let keyCode: CGKeyCode?
  /// Subset of `Hotkey.relevantMask`. `CGEventFlags` is a frozen `UInt64`
  /// `OptionSet` but isn't formally `Sendable`, so the enclosing struct is
  /// `@unchecked Sendable`.
  let modifiers: CGEventFlags
  /// For bare-modifier hotkeys that must tell left from right (or Fn): the
  /// physical key whose `flagsChanged` we match. `nil` matches on flags alone.
  let modifierKeyCode: CGKeyCode?

  init(keyCode: CGKeyCode?, modifiers: CGEventFlags, modifierKeyCode: CGKeyCode? = nil) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.modifierKeyCode = modifierKeyCode
  }

  /// The five modifier bits we care about. Anything else (numericPad, help,
  /// caps lock, …) is masked out before comparisons so cosmetic state on
  /// the event doesn't break matching.
  static let relevantMask: CGEventFlags = [
    .maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn,
  ]

  var isBareModifier: Bool { keyCode == nil }
}
