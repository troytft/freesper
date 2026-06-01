import Carbon.HIToolbox
import CoreGraphics

/// `rawValue` is what's persisted in UserDefaults — keep these stable across
/// releases. New options can be appended freely.
enum HotkeyPreset: String, CaseIterable, Codable, Sendable {
  case rightOption
  case leftOption
  case leftControl
  case fn
  case rightCommand
  case rightShift

  static let `default`: HotkeyPreset = .fn

  var hotkey: Hotkey {
    switch self {
    case .rightOption:
      return Hotkey(
        keyCode: nil, modifiers: .maskAlternate, modifierKeyCode: CGKeyCode(kVK_RightOption))
    case .leftOption:
      return Hotkey(keyCode: nil, modifiers: .maskAlternate, modifierKeyCode: CGKeyCode(kVK_Option))
    case .leftControl:
      return Hotkey(keyCode: nil, modifiers: .maskControl, modifierKeyCode: CGKeyCode(kVK_Control))
    case .fn:
      return Hotkey(
        keyCode: nil, modifiers: .maskSecondaryFn, modifierKeyCode: CGKeyCode(kVK_Function))
    case .rightCommand:
      return Hotkey(
        keyCode: nil, modifiers: .maskCommand, modifierKeyCode: CGKeyCode(kVK_RightCommand))
    case .rightShift:
      return Hotkey(
        keyCode: nil, modifiers: .maskShift, modifierKeyCode: CGKeyCode(kVK_RightShift))
    }
  }

  var label: String {
    switch self {
    case .rightOption: return "Right ⌥"
    case .leftOption: return "Left ⌥"
    case .leftControl: return "Left ⌃"
    case .fn: return "Fn"
    case .rightCommand: return "Right ⌘"
    case .rightShift: return "Right ⇧"
    }
  }
}
