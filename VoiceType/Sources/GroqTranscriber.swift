import Foundation

struct GroqTranscriber {
    private let model = "whisper-large-v3"
    private let language = "en"
    private let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!

    // MARK: - API Key (~/.config/voicetype/api-key)

    private static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/voicetype")
    private static let apiKeyFile = configDir.appendingPathComponent("api-key")

    static func saveAPIKey(_ key: String) {
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        // File only readable by owner
        let data = Data(key.utf8)
        FileManager.default.createFile(atPath: apiKeyFile.path, contents: data,
                                       attributes: [.posixPermissions: 0o600])
    }

    static func loadAPIKey() -> String? {
        if let envKey = ProcessInfo.processInfo.environment["GROQ_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        guard let data = try? Data(contentsOf: apiKeyFile) else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Transcription

    func transcribe(wavData: Data, apiKey: String) async throws -> String {
        let boundary = UUID().uuidString

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // file field
        body.appendMultipart(boundary: boundary, name: "file", filename: "recording.wav",
                             contentType: "audio/wav", data: wavData)

        // model field
        body.appendMultipart(boundary: boundary, name: "model", value: model)

        // language field
        body.appendMultipart(boundary: boundary, name: "language", value: language)

        // prompt hint for punctuation style
        body.appendMultipart(boundary: boundary, name: "prompt",
                             value: "Use proper punctuation: commas, periods, question marks, exclamation points, colons, and semicolons.")

        // close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let json = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return json.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct TranscriptionResponse: Decodable {
    let text: String
}

enum TranscriptionError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Groq API"
        case .apiError(let code, let message):
            return "Groq API error (\(code)): \(message)"
        }
    }
}

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, filename: String,
                                  contentType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}
