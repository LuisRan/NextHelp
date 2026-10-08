import Foundation

/// Log de diagnóstico a archivo (además de la consola), para poder revisarlo
/// sin depender de la consola de Xcode, que se inunda con mensajes de
/// ScreenCaptureKit. Como la app ya no tiene App Sandbox, puede escribir en
/// la carpeta del proyecto:
///   ~/Documents/MeetingAssistant/MeetingAssistant-debug.log
enum DebugLog {
    nonisolated static let fileURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Documents/MeetingAssistant/MeetingAssistant-debug.log")

    nonisolated private static let queue = DispatchQueue(label: "DebugLog")

    /// Borra el log (se llama al arrancar la app).
    nonisolated static func reset() {
        queue.sync {
            try? Data().write(to: fileURL)
        }
    }

    nonisolated static func log(_ message: String) {
        let now = Date()
        print(message)
        queue.async {
            let df = DateFormatter()
            df.dateFormat = "HH:mm:ss.SSS"
            let line = "[\(df.string(from: now))] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    /// Describe un error con dominio y código (los códigos de Speech son la
    /// pista clave: 1110 = no speech, 216/301 = cancelado, 1107/203 = servidor).
    nonisolated static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) code=\(ns.code) \"\(ns.localizedDescription)\""
    }
}
