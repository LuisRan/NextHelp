import Foundation

enum Speaker: String, Codable {
    case me = "Tú"
    case them = "Ellos"
}

struct TranscriptSegment: Identifiable, Codable {
    let id: UUID
    let speaker: Speaker
    var text: String
    let timestamp: Date
    /// false mientras el motor todavía puede corregir el texto (resultado
    /// "en progreso"). Se muestra y se usa igual, para no esperar.
    var isFinal: Bool
    /// true si lo corregiste a mano (se muestra con un lápiz).
    var edited: Bool

    init(speaker: Speaker, text: String, timestamp: Date = Date(), isFinal: Bool = true) {
        self.id = UUID()
        self.speaker = speaker
        self.text = text
        self.timestamp = timestamp
        self.isFinal = isFinal
        self.edited = false
    }
}
