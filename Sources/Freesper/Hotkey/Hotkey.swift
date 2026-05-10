import CoreGraphics

enum HotkeyMode: String, Codable, Sendable, CaseIterable {
  case hold
  case toggle
}

struct Hotkey: Equatable, @unchecked Sendable {
  /// `nil` means "bare modifier hotkey" — match a flagsChanged transition.
  let keyCode: CGKeyCode?
  /// Subset of `Hotkey.relevantMask`. `CGEventFlags` is a frozen `UInt64`
  /// `OptionSet` but isn't formally `Sendable`, so the enclosing struct is
  /// `@unchecked Sendable`.
  let modifiers: CGEventFlags

  /// The five modifier bits we care about. Anything else (numericPad, help,
  /// caps lock, …) is masked out before comparisons so cosmetic state on
  /// the event doesn't break matching.
  static let relevantMask: CGEventFlags = [
    .maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn,
  ]

  var isBareModifier: Bool { keyCode == nil }
}
