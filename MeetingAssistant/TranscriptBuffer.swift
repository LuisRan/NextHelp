import Foundation
import Combine

/// Buffer cronológico único donde caen los segmentos de AMBAS fuentes
/// (tu micrófono y el audio del sistema), cada uno con su etiqueta de
/// hablante. Es lo que se lee para armar el "recent_context" que se
/// manda al servicio RAG.
@MainActor
final class TranscriptBuffer: ObservableObject {
    @Published private(set) var segments: [TranscriptSegment] = []

    // Tope alto: la reunión completa se guarda en .txt y el chat la lee toda.
    private let maxSegmentsKept = 5000

    /// Segmento "en progreso" de cada hablante (uno máximo por hablante).
    private var liveSegmentID: [Speaker: UUID] = [:]

    func append(_ segment: TranscriptSegment) {
        segments.append(segment)
        if segments.count > maxSegmentsKept {
            segments.removeFirst(segments.count - maxSegmentsKept)
        }
    }

    /// Texto en progreso: aparece en el transcript DE INMEDIATO y se va
    /// actualizando mientras la persona habla, sin esperar a que el motor
    /// lo confirme (eso tarda ~10 s en habla continua).
    func updateLive(_ speaker: Speaker, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = liveSegmentID[speaker], let i = segments.firstIndex(where: { $0.id == id }) {
            if trimmed.isEmpty {
                segments.remove(at: i)
                liveSegmentID[speaker] = nil
            } else {
                segments[i].text = trimmed
            }
        } else {
            liveSegmentID[speaker] = nil
            guard !trimmed.isEmpty else { return }
            let segment = TranscriptSegment(speaker: speaker, text: trimmed, isFinal: false)
            liveSegmentID[speaker] = segment.id
            append(segment)
        }
    }

    /// Texto confirmado por el motor: reemplaza al que estaba en progreso
    /// (misma línea, ya corregida) o se agrega si no había uno.
    func commitFinal(_ speaker: Speaker, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = liveSegmentID[speaker], let i = segments.firstIndex(where: { $0.id == id }) {
            liveSegmentID[speaker] = nil
            if trimmed.isEmpty {
                segments.remove(at: i)
            } else {
                segments[i].text = trimmed
                segments[i].isFinal = true
            }
        } else {
            liveSegmentID[speaker] = nil
            guard !trimmed.isEmpty else { return }
            append(TranscriptSegment(speaker: speaker, text: trimmed))
        }
    }

    /// Corrige a mano el texto de una línea (si queda vacío, se borra).
    func editText(id: UUID, to newText: String) {
        guard let i = segments.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            remove(ids: [id])
            return
        }
        if segments[i].text != trimmed {
            segments[i].text = trimmed
            segments[i].edited = true
        }
    }

    /// Borra las líneas indicadas.
    func remove(ids: Set<UUID>) {
        segments.removeAll { ids.contains($0.id) }
        for (speaker, id) in liveSegmentID where ids.contains(id) {
            liveSegmentID[speaker] = nil
        }
    }

    /// Toda la reunión como texto, una línea por frase con hora y hablante.
    func fullText() -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return segments
            .map { "[\(df.string(from: $0.timestamp))] \($0.speaker.rawValue): \($0.text)" }
            .joined(separator: "\n")
    }

    /// Vacía la transcripción (al empezar una reunión nueva).
    func clearAll() {
        segments.removeAll()
        liveSegmentID.removeAll()
    }

    /// Los últimos `count` segmentos (incluye lo que se está diciendo ahora),
    /// formateados como texto plano etiquetado, listo para el prompt.
    func recentContext(count: Int = 6) -> String {
        segments.suffix(count)
            .map { "\($0.speaker.rawValue): \($0.text)" }
            .joined(separator: "\n")
    }

    /// Lo último que dijo la otra persona, incluyendo lo que está diciendo
    /// AHORA. Junta los últimos pedazos recientes para no cortar una
    /// pregunta que quedó partida entre dos frases del motor.
    func recentFromThem(maxPieces: Int = 3, within seconds: TimeInterval = 60) -> String? {
        let theirs = segments.filter { $0.speaker == .them }
        guard let last = theirs.last else { return nil }
        let cutoff = last.timestamp.addingTimeInterval(-seconds)
        let pieces = theirs.suffix(maxPieces).filter { $0.timestamp >= cutoff }.map(\.text)
        return pieces.joined(separator: " ")
    }

    /// La última frase de la otra persona (se conserva por compatibilidad).
    var lastFromThem: String? {
        segments.last(where: { $0.speaker == .them })?.text
    }
}
