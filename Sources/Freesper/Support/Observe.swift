import Observation

/// Re-arming wrapper around `withObservationTracking`. The standard call is
/// one-shot — the closure fires exactly once, then the tracker forgets you.
/// `observe` re-arms after each fire so a single call sets up an ongoing
/// subscription, and runs `onChange` on the main actor.
///
/// `access` should *touch* every observed property (a discarded read is fine);
/// any change to those properties triggers `onChange`.
@MainActor
func observe(
  _ access: @escaping @MainActor () -> Void,
  onChange: @escaping @MainActor () -> Void
) {
  withObservationTracking(access) {
    Task { @MainActor in
      observe(access, onChange: onChange)
      onChange()
    }
  }
}
