import Foundation
import OSLog

// MARK: - Logging
//
// Everything goes to stdout (for `./run.sh`) and to the unified log (for
// `./run-bundle.sh`, where stdout is not attached to a terminal).

let osLogger = Logger(subsystem: "com.github.adfd3ewdf3.FinderBack", category: "tap")

/// Per-event tracing is OFF unless you pass --debug. It fires on every click and
/// every keystroke on the machine, so leaving it on costs a string build and two
/// writes per event for the entire time the app is running.
let verboseLogging = CommandLine.arguments.contains("--debug")

/// @autoclosure matters here: with tracing off, the interpolated string is never
/// even built. A plain String parameter would be constructed at every call site
/// regardless and then thrown away.
func dbg(_ msg: @autoclosure () -> String) {
    guard verboseLogging else { return }
    emit(msg())
}

/// Lifecycle and failures — always shown, however the app was launched.
func info(_ msg: String) {
    emit(msg)
}

private func emit(_ msg: String) {
    let t = Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 10_000)
    print(String(format: "[%9.3f] %@", t, msg))
    fflush(stdout)
    osLogger.log("\(msg, privacy: .public)")
}
