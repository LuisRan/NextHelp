import SwiftUI
import Combine

/// Una respuesta del asistente, para el historial del panel derecho.
struct AnswerEntry: Identifiable {
    let id = UUID()
    let question: String
    let answer: String?
    let error: String?
    let profile: String
    let sources: [String]
    /// "Respuesta" (a un fragmento) o "Chat" (pregunta libre tuya).
    var kind: String = "Respuesta"
    let date = Date()
}

struct ContentView: View {
    @StateObject private var buffer = TranscriptBuffer()
    private let micService = MicCaptureService()
    private let systemAudioService = SystemAudioCaptureService()

    @State private var micMuted = false
    @State private var systemMuted = false
    /// Línea que estás corrigiendo a mano (nil = ninguna).
    @State private var editingID: UUID?
    @State private var editText = ""
    @FocusState private var editorFocused: Bool
    @State private var profile = "servicenow"
    /// "general" siempre disponible aunque el backend todavía no responda.
    @State private var availableProfiles: [String] = ["general", "servicenow"]
    @State private var isAsking = false
    @State private var errorText: String?
    /// Líneas que elegiste a mano para responder (clic para marcar/desmarcar).
    @State private var selectedIDs: Set<UUID> = []
    /// Historial de respuestas, la más nueva arriba.
    @State private var answers: [AnswerEntry] = []
    /// Tu aclaración opcional para "Responder" (ej. "se refiere a Change Management").
    @State private var hintText = ""
    /// Pregunta libre sobre la reunión (chat del panel derecho).
    @State private var chatText = ""
    @State private var isChatting = false
    /// Guarda la transcripción en .txt automáticamente.
    @State private var saver = TranscriptSaver()
    @State private var meetingStart = Date()
    /// Teleprompter para demos en vivo (tercer panel).
    @StateObject private var teleprompter = Teleprompter()
    @State private var showTeleprompter = true
    /// La ventana no aparece cuando compartes pantalla (para que no vean tu guion).
    @State private var hideFromScreenShare = true
    /// La ventana flota encima de las demás apps (también en pantalla completa).
    @State private var alwaysOnTop = false
    /// Transparencia de la ventana (1 = opaca).
    @State private var windowOpacity = 1.0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                transcriptPanel
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                answerPanel
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                if showTeleprompter {
                    teleprompterPanel
                        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: showTeleprompter ? 1150 : 780, minHeight: 520)
        .background(WindowControl(hiddenFromCapture: hideFromScreenShare,
                                  alwaysOnTop: alwaysOnTop,
                                  opacity: windowOpacity))
        .onReceive(buffer.$segments) { segments in
            // Guardado automático del .txt (unos segundos después de cada cambio).
            saver.scheduleSave(text: { buffer.fullText() }, header: { fileHeader() })
            // El teleprompter avanza según lo que vas diciendo (tu mic).
            // (Se usa `segments`: el valor NUEVO; buffer.segments aún es el viejo aquí.)
            teleprompter.observe(segments)
        }
        .task { await loadProfiles() }
        .task { await startCapture() }
    }

    // MARK: - Barra superior

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Perfil", selection: $profile) {
                ForEach(availableProfiles, id: \.self) { Text($0).tag($0) }
            }
            .frame(maxWidth: 240)

            Button {
                newMeeting()
            } label: {
                Label("Nueva reunión", systemImage: "plus.bubble")
            }
            .help("Guarda la transcripción actual y empieza una nueva (archivo .txt nuevo)")

            Button {
                saver.saveNow(buffer.fullText(), header: fileHeader())
                saver.revealInFinder()
            } label: {
                Label("Transcripciones", systemImage: "folder")
            }
            .help("Abre la carpeta donde se guardan los .txt de cada reunión")

            Toggle(isOn: $showTeleprompter) {
                Label("Teleprompter", systemImage: "text.alignleft")
            }
            .toggleStyle(.button)
            .help("Muestra u oculta el teleprompter para demos")

            Toggle(isOn: $hideFromScreenShare) {
                Label(hideFromScreenShare ? "Invisible al compartir" : "Visible al compartir",
                      systemImage: hideFromScreenShare ? "eye.slash" : "eye")
            }
            .toggleStyle(.button)
            .help("Si está activo, esta ventana no se ve cuando compartes pantalla")

            Toggle(isOn: $alwaysOnTop) {
                Label("Encima de todo", systemImage: alwaysOnTop ? "pin.fill" : "pin")
            }
            .toggleStyle(.button)
            .help("La ventana flota sobre las demás apps (también en pantalla completa y en todos los escritorios)")

            HStack(spacing: 4) {
                Image(systemName: "circle.lefthalf.filled")
                    .foregroundStyle(.secondary)
                Slider(value: $windowOpacity, in: 0.35...1.0)
                    .frame(width: 80)
                    .controlSize(.small)
            }
            .help("Transparencia de la ventana, para ver lo que hay detrás")

            Spacer()

            Toggle(isOn: $systemMuted) {
                Label(systemMuted ? "Audio interno silenciado" : "Silenciar audio interno",
                      systemImage: systemMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .toggleStyle(.button)
            .help("Deja de transcribir lo que suena en la Mac (\"Ellos\")")
            .onChange(of: systemMuted) { _, newValue in
                systemAudioService.isMuted = newValue
            }

            Toggle(isOn: $micMuted) {
                Label(micMuted ? "Mic muteado" : "Mutear mi mic",
                      systemImage: micMuted ? "mic.slash.fill" : "mic.fill")
            }
            .toggleStyle(.button)
            .onChange(of: micMuted) { _, newValue in
                micService.isMuted = newValue
            }
        }
        .padding(12)
    }

    // MARK: - Panel izquierdo: transcripción

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transcripción").font(.headline)
                Spacer()
                if !selectedIDs.isEmpty {
                    Text("\(selectedIDs.count) seleccionada(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Limpiar") { selectedIDs.removeAll() }
                        .controlSize(.small)
                    Button(role: .destructive) {
                        cancelEdit()
                        buffer.remove(ids: selectedIDs)
                        selectedIDs.removeAll()
                    } label: {
                        Label("Borrar", systemImage: "trash")
                    }
                    .controlSize(.small)
                    .help("Borra de la transcripción las líneas seleccionadas")
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(buffer.segments) { seg in
                            segmentRow(seg).id(seg.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: buffer.segments.last?.id) { _, lastID in
                    // No te muevo la vista mientras estás eligiendo líneas.
                    guard selectedIDs.isEmpty, editingID == nil, let lastID else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }

            Text("Haz clic en una o varias líneas para elegir a qué responder (✏️ para corregirlas). Sin selección, responde a lo último que dijeron \"Ellos\".")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Aclaración opcional (ej. \"se refiere al módulo Change Management\")", text: $hintText)
                .textFieldStyle(.roundedBorder)
                .help("Se usa para buscar en los documentos del perfil y se le pasa al LLM junto con el fragmento")

            HStack(spacing: 8) {
                Button {
                    Task { await askNow() }
                } label: {
                    Label(isAsking ? "Pensando…" : (selectedIDs.isEmpty ? "Responder lo último" : "Responder selección"),
                          systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAsking)
                // ⌘↩ (⌘Espacio lo usa Spotlight y nunca llegaba a la app).
                .keyboardShortcut(.return, modifiers: [.command])

                Text("⌘↩").font(.caption).foregroundStyle(.secondary)
            }

            if let errorText {
                Text(errorText).foregroundStyle(.red).font(.caption)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func segmentRow(_ seg: TranscriptSegment) -> some View {
        if editingID == seg.id {
            editorRow(seg)
        } else {
            normalRow(seg)
        }
    }

    /// Línea en modo edición: Enter guarda, Esc cancela.
    private func editorRow(_ seg: TranscriptSegment) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(seg.speaker.rawValue + ":")
                .fontWeight(.semibold)
                .foregroundStyle(seg.speaker == .them ? Color.accentColor : Color.secondary)
            TextField("Texto", text: $editText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .focused($editorFocused)
                .onSubmit { saveEdit() }
                .onExitCommand { cancelEdit() }
                .onAppear { editorFocused = true }
            Button { saveEdit() } label: {
                Image(systemName: "checkmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Guardar (Enter)")
            Button { cancelEdit() } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Cancelar (Esc)")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.12)))
    }

    private func normalRow(_ seg: TranscriptSegment) -> some View {
        let isSelected = selectedIDs.contains(seg.id)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(seg.speaker.rawValue + ":")
                .fontWeight(.semibold)
                .foregroundStyle(seg.speaker == .them ? Color.accentColor : Color.secondary)
            // En cursiva con "…" mientras el motor aún puede corregirlo.
            Text(seg.text + (seg.isFinal ? "" : " …"))
                .italic(!seg.isFinal)
                .foregroundStyle(seg.speaker == .them ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if seg.edited {
                Image(systemName: "pencil.line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Corregido a mano")
            }
            if isSelected {
                Button { startEdit(seg) } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                // Mientras está en cursiva el motor la sigue reescribiendo y
                // borraría tu corrección: se edita cuando ya se confirmó.
                .disabled(!seg.isFinal)
                .help(seg.isFinal ? "Corregir esta línea" : "Espera a que se confirme (deja de estar en cursiva)")
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedIDs.remove(seg.id)
            } else {
                selectedIDs.insert(seg.id)
            }
        }
    }

    // MARK: - Panel derecho: respuestas

    private var answerPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Respuestas").font(.headline)
                Spacer()
                if isAsking {
                    ProgressView().controlSize(.small)
                }
                if !answers.isEmpty {
                    Button("Borrar") { answers.removeAll() }
                        .controlSize(.small)
                }
            }

            if answers.isEmpty {
                Text(isAsking ? "Pensando…" : "Aquí aparecerán las respuestas.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(answers) { entry in
                            answerCard(entry)
                        }
                    }
                }
            }

            Divider()
            HStack(spacing: 8) {
                TextField("Pregúntale algo sobre la reunión…", text: $chatText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await sendChat() } }
                    .disabled(isChatting)
                Button {
                    Task { await sendChat() }
                } label: {
                    Image(systemName: isChatting ? "hourglass" : "paperplane.fill")
                }
                .disabled(isChatting || chatText.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Pregunta libre: el LLM lee toda la transcripción (y los documentos del perfil)")
            }
        }
        .padding(12)
    }

    private func answerCard(_ entry: AnswerEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: entry.kind == "Chat" ? "bubble.left.and.text.bubble.right" : "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.profile)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.2)))
                Text(entry.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("“\(entry.question)”")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if let answer = entry.answer {
                Text(answer)
                    .textSelection(.enabled)
            }
            if let error = entry.error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if !entry.sources.isEmpty {
                Text("Fuentes: " + entry.sources.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.thinMaterial))
    }

    // MARK: - Panel del teleprompter

    private var teleprompterPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Teleprompter").font(.headline)
                Text(teleprompter.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    teleprompter.openPanel(segments: buffer.segments)
                } label: {
                    Image(systemName: "doc.text")
                }
                .help("Abrir un guion (.md o .txt)")
                Button {
                    teleprompter.revealFolder()
                } label: {
                    Image(systemName: "folder")
                }
                .help("Abrir la carpeta de guiones")
            }

            if teleprompter.steps.isEmpty {
                Text("Abre un guion para empezar.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(teleprompter.steps) { step in
                                stepCard(step)
                                    .id(step.index)
                                    .onTapGesture {
                                        teleprompter.go(to: step.index, segments: buffer.segments)
                                    }
                            }
                        }
                        .padding(.vertical, 60)
                    }
                    .onChange(of: teleprompter.currentIndex) { _, index in
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                    .onAppear {
                        proxy.scrollTo(teleprompter.currentIndex, anchor: .center)
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    teleprompter.previous(segments: buffer.segments)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(teleprompter.currentIndex == 0)
                Text("Paso \(teleprompter.currentIndex + 1) de \(teleprompter.steps.count)")
                    .font(.caption)
                    .monospacedDigit()
                Button {
                    teleprompter.next(segments: buffer.segments)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(teleprompter.currentIndex >= teleprompter.steps.count - 1)
                ProgressView(value: teleprompter.progress)
                    .frame(maxWidth: 110)
                    .help("Qué tanto del paso actual ya dijiste")
                Spacer()
                Toggle("Avance por voz", isOn: $teleprompter.autoAdvance)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        .padding(12)
    }

    private func stepCard(_ step: ScriptStep) -> some View {
        let isCurrent = step.index == teleprompter.currentIndex
        let isPast = step.index < teleprompter.currentIndex
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(step.lines) { line in
                switch line.kind {
                case .heading:
                    Text(line.text)
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                case .say:
                    Text(line.text)
                        .font(isCurrent ? .title2 : .body)
                        .fontWeight(isCurrent ? .medium : .regular)
                case .action:
                    Label(line.text, systemImage: "hand.point.up.left.fill")
                        .font((isCurrent ? Font.title3 : Font.callout).weight(.bold))
                        .foregroundStyle(Color.orange)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isCurrent ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isCurrent ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .opacity(isPast ? 0.4 : 1)
        .contentShape(Rectangle())
    }

    // MARK: - Edición de líneas

    private func startEdit(_ seg: TranscriptSegment) {
        editText = seg.text
        editingID = seg.id
    }

    private func saveEdit() {
        guard let id = editingID else { return }
        buffer.editText(id: id, to: editText)
        editingID = nil
        editorFocused = false
    }

    private func cancelEdit() {
        editingID = nil
        editorFocused = false
    }

    // MARK: - Lógica

    private func loadProfiles() async {
        guard let list = try? await RAGClient.profiles(), !list.isEmpty else { return }
        availableProfiles = list
        if !list.contains(profile), let first = list.first {
            profile = first
        }
    }

    private func startCapture() async {
        DebugLog.reset()
        DebugLog.log("=== App iniciada — log en \(DebugLog.fileURL.path) ===")
        micService.buffer = buffer
        systemAudioService.buffer = buffer

        micService.onError = { message in
            errorText = "Mic: \(message)"
        }
        systemAudioService.onError = { message in
            errorText = "Audio del sistema: \(message)"
        }

        // Cada fuente arranca por separado: si una falla, la otra sigue.
        do {
            try await micService.start()
        } catch {
            DebugLog.log("[APP] ⚠️ mic no arrancó: \(DebugLog.describe(error))")
            errorText = "No se pudo iniciar el micrófono: \(error.localizedDescription)"
        }
        do {
            try await systemAudioService.start()
        } catch {
            DebugLog.log("[APP] ⚠️ audio del sistema no arrancó: \(DebugLog.describe(error))")
            errorText = "No se pudo iniciar el audio del sistema: \(error.localizedDescription)"
        }
    }

    private func askNow() async {
        // Si estabas corrigiendo una línea, se guarda antes de preguntar.
        if editingID != nil { saveEdit() }
        let context = buffer.recentContext(count: 8)
        // Si elegiste líneas a mano, se responde a ESAS (en orden); si no,
        // a lo último que dijeron "Ellos" (incluye lo que están diciendo ahora).
        let selected = buffer.segments.filter { selectedIDs.contains($0.id) }
        let rawQuestion = selected.isEmpty
            ? (buffer.recentFromThem() ?? context)
            : selected.map(\.text).joined(separator: " ")
        let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !question.isEmpty else {
            errorText = "Todavía no hay nada transcrito para responder."
            return
        }
        errorText = nil
        isAsking = true
        defer { isAsking = false }

        let usedProfile = profile
        let hint = hintText.trimmingCharacters(in: .whitespacesAndNewlines)
        let shownQuestion = hint.isEmpty ? question : "\(question)  [aclaración: \(hint)]"
        do {
            let response = try await RAGClient.ask(profile: usedProfile, question: question,
                                                   recentContext: context, hint: hint.isEmpty ? nil : hint,
                                                   demoContext: demoContext())
            let sources = Array(Set((response.sources ?? []).map(\.source))).sorted()
            answers.insert(AnswerEntry(question: shownQuestion, answer: response.answer, error: nil,
                                       profile: usedProfile, sources: sources), at: 0)
            selectedIDs.removeAll()
            hintText = ""
        } catch {
            answers.insert(AnswerEntry(question: shownQuestion, answer: nil,
                                       error: "Error: \(error.localizedDescription)",
                                       profile: usedProfile, sources: []), at: 0)
        }
    }

    // MARK: - Chat libre y archivos

    /// Pregunta libre tuya: el LLM lee toda la transcripción.
    private func sendChat() async {
        let question = chatText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isChatting else { return }
        isChatting = true
        defer { isChatting = false }
        let usedProfile = profile
        do {
            let response = try await RAGClient.chat(profile: usedProfile, question: question,
                                                    transcript: buffer.fullText(),
                                                    demoContext: demoContext())
            let sources = Array(Set((response.sources ?? []).map(\.source))).sorted()
            answers.insert(AnswerEntry(question: question, answer: response.answer, error: nil,
                                       profile: usedProfile, sources: sources, kind: "Chat"), at: 0)
            chatText = ""
        } catch {
            answers.insert(AnswerEntry(question: question, answer: nil,
                                       error: "Error: \(error.localizedDescription)",
                                       profile: usedProfile, sources: [], kind: "Chat"), at: 0)
        }
    }

    /// Guion de la demo (solo si el teleprompter está visible y tiene guion).
    private func demoContext() -> String? {
        showTeleprompter ? teleprompter.contextForLLM() : nil
    }

    private func fileHeader() -> String {
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .short
        df.locale = Locale(identifier: "es_MX")
        return "Reunión — \(df.string(from: meetingStart))\nPerfil: \(profile)"
    }

    /// Guarda la reunión actual y empieza una nueva (transcripción vacía, archivo nuevo).
    private func newMeeting() {
        cancelEdit()
        saver.saveNow(buffer.fullText(), header: fileHeader())
        buffer.clearAll()
        selectedIDs.removeAll()
        answers.removeAll()
        hintText = ""
        meetingStart = Date()
        saver.startNewFile()
    }
}
