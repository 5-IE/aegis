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
        
        if let token = UserDefaults.standard.string(forKey: "eltar-session-key") {
            headers["Authorization"] = token
        }
        
        if !isFormData {
            headers["Content-Type"] = "application/json"
        }
        
        return headers
    }
    
    // Core Request Method (Unified GET, POST, PATCH, DELETE)
    internal func request<T: Codable>(
        _ method: String,
        endpoint: String,
        params: [String: Any]? = nil,
        queryParams: [String: String]? = nil
    ) async throws -> ApiResponse<T> {
        var urlComponents = URLComponents(string: baseURL + endpoint)!
        if let queryParams = queryParams {
            urlComponents.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        
        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = method
        
        let headers = getHeaders(isFormData: params != nil && false)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        if let params = params {
            request.httpBody = try? JSONSerialization.data(withJSONObject: params)
        }
        
        let (data, _) = try await session.data(for: request)
        
        do {
            let decoder = JSONDecoder()
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            decoder.dateDecodingStrategy = .formatted(formatter)
            
            return try decoder.decode(ApiResponse<T>.self, from: data)
        } catch {
            print(error)
            throw ApiError(message: "Decoding failed or server error")
        }
    }
}
