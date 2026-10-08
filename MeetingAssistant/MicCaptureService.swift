import Foundation
import AVFoundation
import CoreAudio
import Speech

/// Contador de diagnóstico del mic (se toca desde el hilo de audio).
enum MicDiag {
    nonisolated(unsafe) static var count = 0
}

/// Captura tu micrófono y lo transcribe en vivo con SpeechAnalyzer (local).
/// Cada frase va al buffer compartido, etiquetada como "Tú".
///
/// Si cambias de micrófono (conectas audífonos, AirPods, un mic USB…),
/// AVAudioEngine se DETIENE solo y en silencio. Aquí se detecta ese cambio
/// y se rearranca la captura con el dispositivo nuevo automáticamente.
@MainActor
final class MicCaptureService: NSObject {
    private var audioEngine = AVAudioEngine()
    private let transcriber = LiveTranscriber(tag: "MIC")
    private var configObserver: NSObjectProtocol?
    private var restartTask: Task<Void, Never>?
    private var restartAttempts = 0
    private var listeningToDeviceChanges = false

    weak var buffer: TranscriptBuffer?

    /// Se llama cuando el pipeline falla, para mostrarlo en la UI.
    var onError: ((String) -> Void)?

    /// En true se sigue capturando el mic pero al transcriptor le llega
    /// silencio (no se transcribe nada de tu voz).
    var isMuted = false

    func start() async throws {
        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        DebugLog.log("[MIC] permiso voz=\(speechStatus.rawValue) mic=\(micStatus.rawValue) (3=autorizado)")

        transcriber.onVolatile = { [weak self] text in
            self?.buffer?.updateLive(.me, text: text)
        }
        transcriber.onFinal = { [weak self] text in
            self?.buffer?.commitFinal(.me, text: text)
        }
        try await transcriber.start()

        try startEngine()
        listenForDefaultInputChanges()
    }

    func stop() {
        restartTask?.cancel()
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        Task { await transcriber.stop() }
    }

    // MARK: - Motor de audio

    private func startEngine() throws {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        DebugLog.log("[MIC] dispositivo: \"\(Self.defaultInputDeviceName())\" — \(format.sampleRate) Hz, \(format.channelCount) canales")
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "MicCapture", code: 3, userInfo: [NSLocalizedDescriptionKey: "El micrófono todavía no está listo"])
        }

        let transcriber = self.transcriber
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let muted = self.isMuted
            MicDiag.count += 1
            if !muted, MicDiag.count % 100 == 1, let ch = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                var sum: Float = 0
                for i in 0..<Int(buffer.frameLength) { sum += ch[i] * ch[i] }
                DebugLog.log("[MIC] buffer #\(MicDiag.count) nivel=\(String(format: "%.4f", (sum / Float(buffer.frameLength)).squareRoot()))")
            }
            transcriber.feed(buffer, silenced: muted)
        }

        // El motor avisa (y se detiene) cuando cambia el hardware de audio.
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleEngineRestart(reason: "cambió la configuración de audio")
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        restartAttempts = 0
        DebugLog.log("[MIC] ✅ audioEngine arrancó")
    }

    /// Espera un momento (el dispositivo nuevo tarda en quedar listo) y
    /// agrupa varios avisos seguidos en un solo reinicio.
    private func scheduleEngineRestart(reason: String, delay: Duration = .milliseconds(500)) {
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.restartEngine(reason: reason)
        }
    }

    private func restartEngine(reason: String) {
        DebugLog.log("[MIC] 🔄 reiniciando micrófono: \(reason)")
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        // Motor nuevo: así queda amarrado al micrófono predeterminado ACTUAL.
        audioEngine = AVAudioEngine()
        do {
            try startEngine()
        } catch {
            restartAttempts += 1
            DebugLog.log("[MIC] ⚠️ no se pudo reiniciar (intento \(restartAttempts)): \(DebugLog.describe(error))")
            if restartAttempts <= 5 {
                scheduleEngineRestart(reason: "reintento", delay: .seconds(1))
            } else {
                onError?("No se pudo reiniciar el micrófono tras cambiar de dispositivo: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Cambio de micrófono predeterminado (Core Audio)

    /// Además del aviso de AVAudioEngine, escuchamos directo a macOS cuando
    /// cambia el micrófono predeterminado (conectar/desconectar audífonos).
    private func listenForDefaultInputChanges() {
        guard !listeningToDeviceChanges else { return }
        listeningToDeviceChanges = true
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.scheduleEngineRestart(reason: "cambió el micrófono predeterminado")
            }
        }
        if status != noErr {
            DebugLog.log("[MIC] ⚠️ no se pudo escuchar cambios de micrófono (status \(status))")
        }
    }

    /// Nombre del micrófono predeterminado actual (para el log).
    private static func defaultInputDeviceName() -> String {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr else {
            return "?"
        }
        var name: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, ptr)
        }
        return status == noErr ? (name as String) : "id \(deviceID)"
    }
}
