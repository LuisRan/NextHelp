import Foundation
import AVFoundation
import ScreenCaptureKit
import Speech

/// Captura el audio que sale del sistema (la otra persona en la llamada)
/// con ScreenCaptureKit y lo transcribe en vivo con SpeechAnalyzer (local).
/// Cada frase terminada va al buffer compartido, etiquetada como "Ellos".
@MainActor
final class SystemAudioCaptureService: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let transcriber = LiveTranscriber(tag: "SIS")

    /// Cola serial propia para los buffers de ScreenCaptureKit.
    nonisolated private let sampleQueue = DispatchQueue(label: "SystemAudioSamples")
    nonisolated(unsafe) private var bufferCount = 0
    nonisolated(unsafe) private var loggedFormat = false
    /// Referencia al transcriptor accesible desde la cola de audio.
    nonisolated(unsafe) private var feedTarget: LiveTranscriber?

    weak var buffer: TranscriptBuffer?

    /// En true se sigue capturando el audio del sistema pero al transcriptor
    /// le llega silencio (no se transcribe nada de "Ellos").
    /// Se lee desde la cola de audio, por eso es nonisolated(unsafe).
    nonisolated(unsafe) var isMuted = false

    /// Se llama cuando el pipeline falla, para mostrarlo en la UI.
    var onError: ((String) -> Void)?

    func start() async throws {
        transcriber.onVolatile = { [weak self] text in
            self?.buffer?.updateLive(.them, text: text)
        }
        transcriber.onFinal = { [weak self] text in
            self?.buffer?.commitFinal(.them, text: text)
        }
        try await transcriber.start()
        feedTarget = transcriber

        // Primera vez que se llama esto, macOS pide permiso de "Screen Recording".
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        DebugLog.log("[SIS] SCShareableContent OK — displays=\(content.displays.count)")
        guard let display = content.displays.first else {
            throw NSError(domain: "SystemAudioCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se encontró un display para capturar"])
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true // no te transcribas a ti mismo
        config.width = 2
        config.height = 2 // no nos importa el video

        stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        // Salida de pantalla registrada solo para que ScreenCaptureKit no
        // inunde la consola con "stream output NOT found. Dropping frame".
        try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream?.startCapture()
        DebugLog.log("[SIS] ✅ startCapture() OK")
    }

    func stop() {
        Task { try? await stream?.stopCapture() }
        Task { await transcriber.stop() }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        DebugLog.log("[SIS] ⚠️ SCStream se detuvo: \(DebugLog.describe(error))")
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid,
              let pcm = Self.makePCMBuffer(from: sampleBuffer) else { return }

        let muted = isMuted
        bufferCount += 1
        if !loggedFormat {
            loggedFormat = true
            DebugLog.log("[SIS] formato del audio del sistema: \(pcm.format.sampleRate) Hz, \(pcm.format.channelCount) canales")
        }
        if !muted, bufferCount % 100 == 1, let ch = pcm.floatChannelData?[0], pcm.frameLength > 0 {
            var sum: Float = 0
            for i in 0..<Int(pcm.frameLength) { sum += ch[i] * ch[i] }
            DebugLog.log("[SIS] buffer #\(bufferCount) nivel=\(String(format: "%.4f", (sum / Float(pcm.frameLength)).squareRoot()))")
        }
        feedTarget?.feed(pcm, silenced: muted)
    }

    /// CMSampleBuffer (ScreenCaptureKit) → AVAudioPCMBuffer (lo que come SpeechAnalyzer).
    nonisolated private static func makePCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let desc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(desc) else { return nil }
        var asbd = asbdPtr.pointee
        guard let format = AVAudioFormat(streamDescription: &asbd) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList)
        guard status == noErr else {
            DebugLog.log("[SIS] ⚠️ no se pudo copiar audio (status \(status))")
            return nil
        }
        return pcm
    }
}
