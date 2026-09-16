import Foundation

/// Nutzt installierte Kommandozeilen-Tools (Claude Code, Codex) – damit läuft die
/// Zusammenfassung über das bestehende Abo der Nutzerin / des Nutzers.
struct CLIClient: LLMClient {
    enum Tool: String { case claude, codex }
    let tool: Tool
    let model: String

    static func locate(_ tool: Tool) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/\(tool.rawValue)",
            "\(home)/.claude/local/\(tool.rawValue)",
            "/opt/homebrew/bin/\(tool.rawValue)",
            "/usr/local/bin/\(tool.rawValue)",
            "\(home)/.npm-global/bin/\(tool.rawValue)",
            "\(home)/.bun/bin/\(tool.rawValue)",
        ]
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return hit }
        // Fallback: Login-Shell fragen (findet z. B. nvm-Installationen)
        let out = try? runShell("command -v \(tool.rawValue)", stdin: nil, timeout: 10)
        let path = out?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.hasPrefix("/") ? path : nil
    }

    func complete(system: String, prompt: String) async throws -> String {
        guard let bin = Self.locate(tool) else {
            throw LLMError(message: tool == .claude
                ? "Claude Code wurde nicht gefunden. Installation: claude.ai/download bzw. docs.claude.com (Claude Code)."
                : "Codex CLI wurde nicht gefunden. Installation: github.com/openai/codex")
        }
        let fullPrompt = system + "\n\n" + prompt
        let q = { (s: String) in "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let modelArg = model.isEmpty ? "" : " --model \(q(model))"

        let cancel = CancelFlag()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try Self.run(tool: tool, bin: bin, modelArg: modelArg, prompt: fullPrompt, cancel: cancel)
            }.value
        } onCancel: {
            cancel.set()
        }
    }

    private static func run(tool: Tool, bin: String, modelArg: String, prompt fullPrompt: String,
                            cancel: CancelFlag) throws -> String {
        let q = { (s: String) in "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        switch tool {
        case .claude:
            let cmd = "\(q(bin)) -p --output-format text --disallowedTools Bash Edit Write WebFetch WebSearch\(modelArg)"
            let r = try runShell(cmd, stdin: fullPrompt, timeout: 1800, cancel: cancel)
            guard r.status == 0, !r.stdout.isEmpty else {
                throw LLMError(message: "Claude Code: \(r.stderr.isEmpty ? r.stdout : r.stderr)".prefix(500).description)
            }
            return r.stdout
        case .codex:
            let outFile = FileManager.default.temporaryDirectory.appendingPathComponent("earmark-codex-\(UUID().uuidString).txt")
            defer { try? FileManager.default.removeItem(at: outFile) }
            let cmd = "\(q(bin)) exec --skip-git-repo-check --output-last-message \(q(outFile.path))\(modelArg) -"
            let r = try runShell(cmd, stdin: fullPrompt, timeout: 1800, cancel: cancel)
            let text = (try? String(contentsOf: outFile, encoding: .utf8)) ?? ""
            guard r.status == 0, !text.isEmpty else {
                throw LLMError(message: "Codex: \(r.stderr.suffix(500))")
            }
            return text
        }
    }
}

/// Signal zum Abbrechen eines laufenden Befehls (aus einem anderen Thread gesetzt).
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

struct ShellResult { var status: Int32; var stdout: String; var stderr: String }

/// Führt einen Befehl in einer Login-Shell aus (damit PATH wie im Terminal gesetzt ist).
func runShell(_ command: String, stdin: String?, timeout: TimeInterval, cancel: CancelFlag? = nil) throws -> ShellResult {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
    p.arguments = ["-lc", command]
    p.currentDirectoryURL = FileManager.default.temporaryDirectory
    let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
    p.standardOutput = outPipe
    p.standardError = errPipe
    p.standardInput = inPipe

    final class Box: @unchecked Sendable { var data = Data() }
    let outBox = Box(), errBox = Box()
    let group = DispatchGroup()
    group.enter(); group.enter()
    DispatchQueue.global().async { outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
    DispatchQueue.global().async { errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }

    try p.run()
    let input = stdin
    DispatchQueue.global().async {
        if let input, let data = input.data(using: .utf8) {
            inPipe.fileHandleForWriting.write(data)
        }
        try? inPipe.fileHandleForWriting.close()
    }
    let deadline = Date().addingTimeInterval(timeout)
    while p.isRunning && Date() < deadline && cancel?.isSet != true { Thread.sleep(forTimeInterval: 0.2) }
    if p.isRunning, cancel?.isSet == true {
        p.terminate()
        throw CancellationError()
    }
    if p.isRunning {
        p.terminate()
        throw LLMError(message: "Zeitüberschreitung beim Ausführen von: \(command.prefix(60))")
    }
    group.wait()
    return ShellResult(status: p.terminationStatus,
                       stdout: String(data: outBox.data, encoding: .utf8) ?? "",
                       stderr: String(data: errBox.data, encoding: .utf8) ?? "")
}
