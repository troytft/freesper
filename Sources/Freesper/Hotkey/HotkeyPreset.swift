import Carbon.HIToolbox
import CoreGraphics

/// `rawValue` is what's persisted in UserDefaults — keep these stable across
/// releases. New options can be appended freely.
enum HotkeyPreset: String, CaseIterable, Codable, Sendable {
  case fn
  case fnSpace
  case fnF13
  case optionSpace
  case controlSpace
  case commandShiftSpace
  case f5
  case f13

  static let `default`: HotkeyPreset = .optionSpace

  var hotkey: Hotkey {
    switch self {
    case .fn:
      return Hotkey(keyCode: nil, modifiers: .maskSecondaryFn)
    case .fnSpace:
      return Hotkey(keyCode: CGKeyCode(kVK_Space), modifiers: .maskSecondaryFn)
    case .fnF13:
      return Hotkey(keyCode: CGKeyCode(kVK_F13), modifiers: .maskSecondaryFn)
    case .optionSpace:
      return Hotkey(keyCode: CGKeyCode(kVK_Space), modifiers: .maskAlternate)
    case .controlSpace:
      return Hotkey(keyCode: CGKeyCode(kVK_Space), modifiers: .maskControl)
    case .commandShiftSpace:
      return Hotkey(keyCode: CGKeyCode(kVK_Space), modifiers: [.maskCommand, .maskShift])
    case .f5:
      return Hotkey(keyCode: CGKeyCode(kVK_F5), modifiers: [])
    case .f13:
      return Hotkey(keyCode: CGKeyCode(kVK_F13), modifiers: [])
    }
  }

  var label: String {
    switch self {
    case .fn: return "Fn"
    case .fnSpace: return "Fn + Space"
    case .fnF13: return "Fn + F13"
    case .optionSpace: return "⌥ Space"
    case .controlSpace: return "⌃ Space"
    case .commandShiftSpace: return "⌘⇧ Space"
    case .f5: return "F5"
    case .f13: return "F13"
    }
  }
}
