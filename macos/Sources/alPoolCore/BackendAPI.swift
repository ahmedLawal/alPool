import Foundation

public final class BackendAPI: @unchecked Sendable {
    private let connection: BackendConnection
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(connection: BackendConnection, session: URLSession = .shared) {
        self.connection = connection
        self.session = session
    }

    public func snapshot() async throws -> ControlSnapshot {
        let request = makeRequest(method: "GET")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(ControlSnapshot.self, from: data)
    }

    public func send(_ command: ControlCommand) async throws -> ControlResponse {
        var request = makeRequest(method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try encoder.encode(command)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(ControlResponse.self, from: data)
    }

    private func makeRequest(method: String) -> URLRequest {
        var request = URLRequest(url: connection.baseURL.appending(path: "maxpool/control"))
        request.httpMethod = method
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(connection.apiKey, forHTTPHeaderField: "x-api-key")
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            if let body = try? decoder.decode(ControlResponse.self, from: data), let error = body.error {
                throw error
            }
            throw URLError(.badServerResponse)
        }
    }
}
