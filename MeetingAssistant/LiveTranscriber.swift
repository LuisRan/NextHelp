import Foundation
import AVFoundation
import Speech

/// Transcriptor en vivo basado en SpeechAnalyzer + SpeechTranscriber
/// (macOS 26+). Reemplaza a SFSpeechRecognizer porque:
///   • SFSpeechRecognizer solo permite UNA transcripción activa por app:
///     al arrancar la del sistema, moría la del mic (y viceversa) con
///     "No speech detected" ~30 ms después. El log lo mostró clarísimo.
///   • SpeechAnalyzer corre 100% local, sin límite de duración ni de
///     requests, y cada instancia es independiente (mic + sistema a la vez).
@MainActor
final class LiveTranscriber {
    let tag: String
    private let preferredLocale: Locale

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var resultsTask: Task<Void, Never>?

    // Se usan desde el hilo de audio (feed). Se configuran en start() ANTES
    // de que empiece a llegar audio, y después solo se leen desde ese hilo.
    nonisolated(unsafe) private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    nonisolated(unsafe) private var analyzerFormat: AVAudioFormat?
    nonisolated(unsafe) private var converter: AVAudioConverter?
    nonisolated(unsafe) private var fedBuffers = 0

    /// Texto "en progreso" (cambia mientras la persona habla).
    var onVolatile: ((String) -> Void)?
    /// Frase terminada y definitiva.
    var onFinal: ((String) -> Void)?

    init(tag: String, locale: Locale = Locale(identifier: "es-MX")) {
        self.tag = tag
        self.preferredLocale = locale
    }

    func start() async throws {
        // 1) Elegir un locale soportado (es-MX, o el español que haya).
        let supported = await SpeechTranscriber.supportedLocales
        let wanted = preferredLocale.identifier(.bcp47)
        guard let locale = supported.first(where: { $0.identifier(.bcp47) == wanted })
                ?? supported.first(where: { $0.language.languageCode?.identifier == "es" }) else {
            throw NSError(domain: "LiveTranscriber", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "SpeechTranscriber no soporta español en esta Mac. Soportados: \(supported.map { $0.identifier(.bcp47) })"])
        }
        DebugLog.log("[\(tag)] SpeechTranscriber locale=\(locale.identifier(.bcp47))")

        let transcriber = SpeechTranscriber(locale: locale,
                                            transcriptionOptions: [],
                                            reportingOptions: [.volatileResults, .fastResults], // prioriza velocidad
                                            attributeOptions: [])

        // 2) Descargar el modelo local si no está instalado (solo la 1a vez).
        let installed = await SpeechTranscriber.installedLocales
        if !installed.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
            DebugLog.log("[\(tag)] descargando modelo de voz \(locale.identifier(.bcp47))… (solo la primera vez)")
        }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
            DebugLog.log("[\(tag)] modelo instalado")
        }

        // 3) Formato de audio que quiere el analizador.
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw NSError(domain: "LiveTranscriber", code: 2, userInfo: [NSLocalizedDescriptionKey: "No hay formato de audio compatible con SpeechAnalyzer"])
        }
        analyzerFormat = format
        DebugLog.log("[\(tag)] formato del analizador: \(format.sampleRate) Hz, \(format.channelCount) canales")

        // 4) Resultados.
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    guard let self else { return }
                    if result.isFinal {
                        DebugLog.log("[\(self.tag)] ✅ FINAL: \"\(text)\"")
                        self.onFinal?(text)
                    } else {
                        self.onVolatile?(text)
                    }
                }
                DebugLog.log("[\(self?.tag ?? "?")] stream de resultados terminó")
            } catch {
                DebugLog.log("[\(self?.tag ?? "?")] ⚠️ error en resultados: \(DebugLog.describe(error))")
            }
        }

        // 5) Arrancar con un stream de entrada al que le iremos metiendo audio.
        let (inputSequence, builder) = AsyncStream<AnalyzerInput>.makeStream()
        inputBuilder = builder
        try await analyzer.start(inputSequence: inputSequence)

        self.analyzer = analyzer
        self.transcriber = transcriber
        DebugLog.log("[\(tag)] ✅ SpeechAnalyzer arrancó")
    }

    /// Mete audio al transcriptor. Se llama desde el hilo de audio.
    /// Con `silenced` se manda SILENCIO en vez del audio real: así el
    /// transcriptor cierra limpio la frase que iba a medias (en vez de
    /// quedarse esperando) y no transcribe nada mientras esté silenciado.
    nonisolated func feed(_ buffer: AVAudioPCMBuffer, silenced: Bool = false) {
        guard let inputBuilder, let analyzerFormat else { return }
        guard let converted = convert(buffer, to: analyzerFormat) else { return }
        if silenced {
            for audioBuffer in UnsafeMutableAudioBufferListPointer(converted.mutableAudioBufferList) {
                if let data = audioBuffer.mData {
                    memset(data, 0, Int(audioBuffer.mDataByteSize))
                }
            }
        }
        fedBuffers += 1
        if fedBuffers == 1 {
            DebugLog.log("[\(tag)] primer buffer entregado al analizador")
        }
        inputBuilder.yield(AnalyzerInput(buffer: converted))
    }

    func stop() async {
        inputBuilder?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()
    }

    /// Convierte al formato del analizador (sample rate / canales).
    nonisolated private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        if converter == nil || converter?.inputFormat != buffer.format || converter?.outputFormat != format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            DebugLog.log("[\(tag)] ⚠️ conversión de audio falló: \(error.map { DebugLog.describe($0) } ?? "?")")
            return nil
        }
        return output
    }
}
