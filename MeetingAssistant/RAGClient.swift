import Foundation

struct AskResponse: Decodable {
    let answer: String
    let sources: [Source]?

    struct Source: Decodable {
        let source: String
        let distance: Double
    }
}

enum RAGClient {
    static let baseURL = URL(string: "http://localhost:8000")!

    /// Responder a un fragmento de la reunión (lo último o lo que seleccionaste).
    /// `hint` = tu aclaración opcional (ej. "se refiere al módulo Change Management").
    static func ask(profile: String, question: String, recentContext: String?, hint: String? = nil,
                    demoContext: String? = nil) async throws -> AskResponse {
        try await post("ask", body: [
            "profile": profile,
            "question": question,
            "recent_context": recentContext,
            "hint": hint,
            "demo_context": demoContext,
        ])
    }

    /// Pregunta libre tuya sobre toda la reunión.
    static func chat(profile: String, question: String, transcript: String,
                     demoContext: String? = nil) async throws -> AskResponse {
        try await post("chat", body: [
            "profile": profile,
            "question": question,
            "transcript": transcript,
            "demo_context": demoContext,
        ])
    }

    static func profiles() async throws -> [String] {
        let (data, _) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("profiles"))
        struct Resp: Decodable { let profiles: [String] }
        return try JSONDecoder().decode(Resp.self, from: data).profiles
    }

    private static func post(_ path: String, body: [String: Any?]) async throws -> AskResponse {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        // El backend espera hasta 90 s a Ollama (carga en frío); la app no
        // debe rendirse antes (el default de URLSession es 60 s).
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body.compactMapValues { $0 })

        let (data, _) = try await URLSession.shared.data(for: req)

        if let response = try? JSONDecoder().decode(AskResponse.self, from: data) {
            return response
        }
        // El backend puede regresar {"error": "..."} en vez de {"answer": ...}.
        struct BackendError: Decodable { let error: String }
        if let backendError = try? JSONDecoder().decode(BackendError.self, from: data) {
            throw NSError(domain: "RAGClient", code: 1, userInfo: [NSLocalizedDescriptionKey: backendError.error])
        }
        let raw = String(data: data, encoding: .utf8) ?? "(respuesta no legible)"
        throw NSError(domain: "RAGClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "Respuesta inesperada del servidor: \(raw)"])
    }
}
