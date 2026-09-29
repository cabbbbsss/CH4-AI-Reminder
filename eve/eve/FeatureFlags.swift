//
//  FeatureFlags.swift
//  Eve
//

/// Build-time switches for surfaces that are hidden rather than deleted.
///
/// The repository has twice hidden something by commenting it out — the
/// Settings diagnostics and the Prompt Tester entry point — which leaves dead
/// comments behind and loses the code's compile coverage. These flags do the
/// same job in a way the compiler still checks, and flip back with one edit.
enum FeatureFlags {

    /// The ladybug entry to `PromptTesterView` in the Today header, and the
    /// Notification Diagnostics section in Settings.
    ///
    /// Both sites are inside `#if DEBUG` as well, so a release build never had
    /// them either way. This is what keeps them out of a *debug* build being
    /// demoed or handed to someone.
    ///
    /// Turn on to reach the free-vs-Plus prompt comparison, or to fire a
    /// learning notification in five seconds instead of waiting for a real
    /// calendar event.
    static let showDebugTools = false

}
