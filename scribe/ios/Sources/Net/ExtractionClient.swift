import Foundation

/// Calls the Scribe backend's `POST /extract` to turn a transcript into
/// proposed calendar events and reminders.
struct ExtractionClient {
    let baseURL: URL

    private struct RequestBody: Encodable {
        let transcript: String
        let now: String
        let timeZone: String
    }

    enum ClientError: LocalizedError {
        case server(status: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .server(let status, let message):
                return "Backend error (\(status)): \(message)"
            }
        }
    }

    func extract(transcript: String) async throws -> ExtractionResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("extract"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body = RequestBody(
            transcript: transcript,
            now: ISO8601DateFormatter().string(from: Date()),
            timeZone: TimeZone.current.identifier
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.server(status: -1, message: "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClientError.server(status: http.statusCode, message: message)
        }
        return try JSONDecoder().decode(ExtractionResult.self, from: data)
    }
}
