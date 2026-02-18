import Foundation

/// Writes one NDJSON line to the debug log for this session. Path is inside workspace.
func debugSessionLog(location: String, message: String, data: [String: Int], hypothesisId: String, runId: String = "run1") {
    // #region agent log
    let logPath = "/Users/ricardolopeznovelo/Documents/XCode Projects/Names-3/.cursor/debug.log"
    let timestamp = Int(Date().timeIntervalSince1970 * 1000)
    let dataPairs = data.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",")
    let locEsc = location.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let msgEsc = message.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let line = "{\"timestamp\":\(timestamp),\"location\":\"\(locEsc)\",\"message\":\"\(msgEsc)\",\"data\":{\(dataPairs)},\"sessionId\":\"debug-session\",\"runId\":\"\(runId)\",\"hypothesisId\":\"\(hypothesisId)\"}\n"
    guard let d = line.data(using: .utf8) else { return }
    let dir = (logPath as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: logPath) {
        if let h = FileHandle(forWritingAtPath: logPath) {
            h.seekToEndOfFile()
            h.write(d)
            try? h.close()
        }
    } else {
        FileManager.default.createFile(atPath: logPath, contents: d, attributes: nil)
    }
    // #endregion
}
