//
//  HttpService.swift
//  eltar-mobile
//
//  Created by Steve Agustinus on 21/03/26.
//


import Foundation

class HttpService {
    private let baseURL = AppEnvironment.current.baseURL
    private let session = URLSession.shared
    
    private func getHeaders(isFormData: Bool = false) -> [String: String] {
        var headers: [String: String] = [:]
        
        if let token = UserDefaults.standard.string(forKey: "aegis-access-token") {
            headers["Authorization"] = "Bearer " + token
        }
        
        if !isFormData {
            headers["Content-Type"] = "application/json"
        }

        return headers
    }

    /// Endpoints the backend protects with `requireSignature`. Signing other
    /// requests is harmless but wasteful, so keep this to what the server checks.
    private func requiresSignature(_ endpoint: String) -> Bool {
        return endpoint == "/api/v1/presence"
    }
    
    // Core Request Method (Unified GET, POST, PATCH, DELETE)
    internal func request<T: Codable>(
        _ method: String,
        endpoint: String,
        params: [String: Any]? = nil,
        queryParams: [String: String]? = nil,
        isRetry: Bool = false
    ) async throws -> T {
        guard var urlComponents = URLComponents(string: baseURL + endpoint) else {
            throw ApiError(error: "invalid_url", message: "Invalid URL: \(baseURL + endpoint)")
        }
        if let queryParams = queryParams {
            urlComponents.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = urlComponents.url else {
            throw ApiError(error: "invalid_url", message: "Could not construct URL for \(endpoint)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        let headers = getHeaders(isFormData: params != nil && false)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Serialize the body once so the exact bytes we hash are the bytes we
        // send. `bodyData` is Data() for bodyless requests — its SHA-256 is the
        // empty-bytes constant the server also uses.
        let bodyData: Data = (params != nil)
            ? ((try? JSONSerialization.data(withJSONObject: params!)) ?? Data())
            : Data()
        if params != nil {
            request.httpBody = bodyData
        }

        // Device signing: attach X-Timestamp / X-Signature on protected routes.
        // `endpoint` is the path the server signs against (routers mount at
        // /api/v1/...), so pass it verbatim — no host, no query string.
        if requiresSignature(endpoint) {
            if let (ts, sig) = try? CryptoManager.shared.signRequest(
                method: method,
                path: endpoint,
                body: bodyData
            ) {
                request.setValue(ts, forHTTPHeaderField: "X-Timestamp")
                request.setValue(sig, forHTTPHeaderField: "X-Signature")
            }
        }

        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ApiError(error: "internal_server_error", message: "Invalid response from server.")
        }
        
        if let url = urlComponents.url {
            print("\(httpResponse.statusCode) - \(url)")
        }
        
        if httpResponse.statusCode == 401 && !isRetry {
            do {
                if let apiService = self as? ApiServiceProtocol {
                    if let refreshToken = UserDefaults.standard.string(forKey: "aegis-refresh-token") {
                        let authResponse = try await apiService.refreshToken(refreshToken: refreshToken)

                        UserDefaults.standard.set(authResponse.refreshToken, forKey: "aegis-refresh-token")
                        UserDefaults.standard.set(authResponse.accessToken, forKey: "aegis-access-token")

                        return try await self.request(method, endpoint: endpoint, params: params, queryParams: queryParams, isRetry: true)
                    }
                }
            } catch {
                UserDefaults.standard.removeObject(forKey: "aegis-access-token")
                UserDefaults.standard.removeObject(forKey: "aegis-refresh-token")
                throw ApiError(error: "unauthorized", message: "Session expired. Please login again.")
            }
        }
        
        let decoder = JSONDecoder()
        let isoStyle = Date.ISO8601FormatStyle()
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            if let date =  try? Date(dateString, strategy: isoStyle) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string: \(dateString)")
        }
        if (200...299).contains(httpResponse.statusCode) {
            // 204 No Content (e.g. POST /presence) has an empty body. Return an
            // EmptyResponse rather than failing to decode zero bytes.
            if data.isEmpty || httpResponse.statusCode == 204 {
                if let empty = EmptyResponse() as? T {
                    return empty
                }
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                print("Decoding error: \(error)")
                throw ApiError(error: "internal_server_error", message: "Failed to parse data from server")
            }
        } else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                throw ApiError(error: errorJson["error"] as? String, message: errorJson["message"] as? String)
            } else {
                throw ApiError(error: "internal_server_error", message: "Server error: \(httpResponse.statusCode)")
            }
        }
    }
}
