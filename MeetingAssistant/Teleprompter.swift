import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - Formato del guion
//
//   # Título de sección            → encabezado (opcional)
//   Texto normal                   → lo que DICES (se usa para detectar avance)
//   **Texto entre asteriscos**     → lo que HACES en pantalla (acción)
//   (línea en blanco)              → separa un paso del siguiente
//
// Ejemplo:
//   Como podemos observar, estamos en el registro de un case.
//   **Abre el caso CS0001234 y muestra el campo Financial Account**

struct ScriptLine: Identifiable {
    enum Kind { case say, action, heading }
    let id = UUID()
    let kind: Kind
    let text: String
}

struct ScriptStep: Identifiable {
    let id = UUID()
    let index: Int
    let lines: [ScriptLine]
    /// Palabras clave de lo que se DICE en este paso (para el avance por voz).
    let keywords: [String]

    var sayText: String { lines.filter { $0.kind == .say }.map(\.text).joined(separator: " ") }
    var plainText: String {
        lines.map { line in
            switch line.kind {
            case .say: return line.text
            case .action: return "[ACCIÓN: \(line.text)]"
            case .heading: return "## \(line.text)"
            }
        }.joined(separator: "\n")
    }
}

enum ScriptParser {
    static func parse(_ raw: String) -> [ScriptStep] {
        let blocks = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .split(whereSeparator: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        var steps: [ScriptStep] = []
        for block in blocks {
            var lines: [ScriptLine] = []
            for rawLine in block {
                let t = rawLine.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty else { continue }
                if t.hasPrefix("#") {
                    lines.append(ScriptLine(kind: .heading, text: t.trimmingCharacters(in: CharacterSet(charactersIn: "# "))))
                } else if t.hasPrefix("**") && t.hasSuffix("**") && t.count > 4 {
                    lines.append(ScriptLine(kind: .action, text: String(t.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)))
                } else {
                    lines.append(ScriptLine(kind: .say, text: t))
                }
            }
            guard !lines.isEmpty else { continue }
            let say = lines.filter { $0.kind == .say }.map(\.text).joined(separator: " ")
            steps.append(ScriptStep(index: steps.count, lines: lines, keywords: TextMatch.keywords(say)))
        }
        return steps
    }
}

// MARK: - Comparación de texto hablado vs. guion

enum TextMatch {
    /// Palabras que no aportan para saber en qué parte vas.
    static let stopwords: Set<String> = [
        "que", "los", "las", "del", "por", "para", "con", "una", "uno", "unos", "unas", "este", "esta",
        "estos", "estas", "ese", "esa", "eso", "esto", "como", "pero", "mas", "muy", "hay", "ahi", "aqui",
        "donde", "cuando", "tambien", "entonces", "bien", "pues", "vamos", "ver", "podemos", "puede",
        "pueden", "tiene", "tienen", "son", "sus", "nos", "les", "fue", "ser", "estan", "estamos", "sobre",
        "todo", "toda", "todos", "todas", "cual", "cuales", "mismo", "misma", "ya", "the", "and", "for",
        "you", "this", "that", "with",
    ]

    static func words(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_MX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopwords.contains($0) }
    }

    /// Palabras clave únicas en orden de aparición.
    static func keywords(_ text: String) -> [String] {
        var seen = Set<String>()
        return words(text).filter { seen.insert($0).inserted }
    }
}

// MARK: - Estado del teleprompter

@MainActor
final class Teleprompter: ObservableObject {
    static let folderURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Documents/MeetingAssistant/Guiones", isDirectory: true)

    @Published private(set) var title = "Sin guion"
    @Published private(set) var steps: [ScriptStep] = []
    @Published private(set) var currentIndex = 0
    /// Qué tanto del paso actual ya dijiste (0…1).
    @Published private(set) var progress: Double = 0
    @Published var autoAdvance = true

    /// Palabras ya "consumidas" por pasos anteriores, por segmento de la
    /// transcripción; así lo que dijiste en el paso 3 no cuenta para el 4.
    private var baseline: [UUID: Int] = [:]

    /// Porcentaje de palabras clave dichas para pasar al siguiente paso.
    private let advanceThreshold = 0.6

    var currentStep: ScriptStep? { steps.indices.contains(currentIndex) ? steps[currentIndex] : nil }

    init() {
        ensureExampleScript()
    }

    // MARK: Cargar

    func load(url: URL) {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            DebugLog.log("[TELE] ⚠️ no se pudo leer \(url.path)")
            return
        }
        steps = ScriptParser.parse(raw)
        title = url.deletingPathExtension().lastPathComponent
        currentIndex = 0
        progress = 0
        baseline.removeAll()
        DebugLog.log("[TELE] guion cargado: \(title) (\(steps.count) pasos)")
    }

    func openPanel(segments: [TranscriptSegment]) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        panel.directoryURL = Self.folderURL
        panel.message = "Elige el guion de la demo (.txt o .md)"
        if panel.runModal() == .OK, let url = panel.url {
            load(url: url)
            markConsumed(segments)
        }
    }

    func revealFolder() {
        try? FileManager.default.createDirectory(at: Self.folderURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Self.folderURL)
    }

    // MARK: Navegación manual

    func go(to index: Int, segments: [TranscriptSegment]) {
        guard steps.indices.contains(index) else { return }
        currentIndex = index
        progress = 0
        markConsumed(segments)
    }

    func next(segments: [TranscriptSegment]) { go(to: currentIndex + 1, segments: segments) }
    func previous(segments: [TranscriptSegment]) { go(to: currentIndex - 1, segments: segments) }

    // MARK: Avance por voz

    /// Se llama cada vez que cambia la transcripción. Solo cuenta TU voz.
    func observe(_ segments: [TranscriptSegment]) {
        guard let step = currentStep, !step.keywords.isEmpty else { return }
        let spoken = Set(newWords(in: segments))
        let hits = step.keywords.filter { spoken.contains($0) }.count
        let coverage = Double(hits) / Double(step.keywords.count)
        progress = coverage

        guard autoAdvance, currentIndex < steps.count - 1 else { return }
        // Pasos muy cortos: hay que decir todas sus palabras clave.
        let needed = step.keywords.count < 3 ? 1.0 : advanceThreshold
        // Si ya dijiste las últimas palabras del paso, basta con menos cobertura.
        let tail = step.keywords.suffix(2)
        let saidEnding = step.keywords.count >= 4 && tail.allSatisfy { spoken.contains($0) }
        if coverage >= needed || (saidEnding && coverage >= 0.45) {
            DebugLog.log("[TELE] ✅ paso \(currentIndex + 1) dicho (\(Int(coverage * 100))%) → avanzo")
            go(to: currentIndex + 1, segments: segments)
        }
    }

    /// Palabras tuyas dichas DESPUÉS de llegar al paso actual.
    private func newWords(in segments: [TranscriptSegment]) -> [String] {
        segments.filter { $0.speaker == .me }.flatMap { seg -> [String] in
            let w = TextMatch.words(seg.text)
            let used = baseline[seg.id] ?? 0
            return used < w.count ? Array(w[used...]) : []
        }
    }

    /// Marca todo lo dicho hasta ahora como ya usado.
    private func markConsumed(_ segments: [TranscriptSegment]) {
        for seg in segments where seg.speaker == .me {
            baseline[seg.id] = TextMatch.words(seg.text).count
        }
    }

    // MARK: Contexto para el LLM

    /// Guion completo + paso actual, para que la IA responda en contexto de la demo.
    func contextForLLM(maxChars: Int = 3500) -> String? {
        guard !steps.isEmpty else { return nil }
        var full = steps.map { "Paso \($0.index + 1):\n\($0.plainText)" }.joined(separator: "\n\n")
        if full.count > maxChars { full = String(full.prefix(maxChars)) + "\n…" }
        let current = currentStep.map { "Paso \($0.index + 1):\n\($0.plainText)" } ?? ""
        return "Demo: \(title)\n\nPaso en el que va el usuario ahora:\n\(current)\n\nGuion completo:\n\(full)"
    }

    // MARK: Guion de ejemplo

    private func ensureExampleScript() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.folderURL, withIntermediateDirectories: true)
        let example = Self.folderURL.appendingPathComponent("ejemplo_demo_fso.md")
        if !fm.fileExists(atPath: example.path) {
            try? Self.exampleText.write(to: example, atomically: true, encoding: .utf8)
        }
        load(url: example)
    }

    static let exampleText = """
    # Demo FSO — Card Operations

    Buenas tardes a todos, hoy les voy a mostrar cómo Financial Services Operations ayuda al banco a gestionar las solicitudes de tarjetas.
    **Comparte pantalla con el Service Operations Workspace abierto**

    Como podemos observar, estamos en el registro de un case de tarjeta de crédito levantado por un cliente.
    **Abre el caso de Card Operations y señala el campo Financial Account**

    Aquí vemos que el caso está ligado directamente a la cuenta financiera del cliente, con su saldo, su producto y las personas relacionadas.
    **Da clic en la cuenta financiera y muestra la pestaña de partes relacionadas**

    Ahora vamos a reportar la tarjeta como robada para que el sistema genere las tareas de bloqueo y reposición automáticamente.
    **Selecciona la service definition de tarjeta robada y guarda el caso**

    Como ven, el playbook guía al agente paso a paso y el SLA empieza a contar en ese momento.
    **Muestra el playbook y el indicador de SLA**

    Para cerrar, este mismo flujo se integra con el core bancario y con Visa o Mastercard si el cliente abre una disputa.
    **Regresa al caso y muestra la sección de disputas**
    """
}
