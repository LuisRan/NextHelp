import Foundation
import AppKit

/// Guarda la transcripción de cada reunión en un .txt dentro de
///   ~/Documents/MeetingAssistant/Transcripciones/reunion-AAAA-MM-DD_HH-mm.txt
/// Se reescribe completo cada vez que cambia (unos segundos después), así
/// el archivo siempre refleja también tus correcciones y borrados.
@MainActor
final class TranscriptSaver {
    static let folderURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Documents/MeetingAssistant/Transcripciones", isDirectory: true)

    private(set) var fileURL: URL
    private var pendingSave: Task<Void, Never>?

    init() {
        fileURL = Self.makeFileURL()
    }

    /// Empieza un archivo nuevo (botón "Nueva reunión").
    func startNewFile() {
        pendingSave?.cancel()
        fileURL = Self.makeFileURL()
    }

    /// Programa un guardado (agrupa muchos cambios seguidos en uno solo).
    /// El texto se calcula al momento de guardar (no al programar), para no
    /// quedarse con una versión atrasada de la transcripción.
    func scheduleSave(text: @escaping () -> String, header: @escaping () -> String) {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.write(text(), header: header())
        }
    }

    /// Guarda ya (botón "Guardar" o al empezar reunión nueva).
    func saveNow(_ text: String, header: String) {
        pendingSave?.cancel()
        write(text, header: header)
    }

    func revealInFinder() {
        try? FileManager.default.createDirectory(at: Self.folderURL, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            NSWorkspace.shared.open(Self.folderURL)
        }
    }

    private func write(_ text: String, header: String) {
        guard !text.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: Self.folderURL, withIntermediateDirectories: true)
            try (header + "\n\n" + text + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            DebugLog.log("[TXT] ⚠️ no se pudo guardar la transcripción: \(DebugLog.describe(error))")
        }
    }

    private static func makeFileURL() -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HH-mm"
        return folderURL.appendingPathComponent("reunion-\(df.string(from: Date())).txt")
    }
}
