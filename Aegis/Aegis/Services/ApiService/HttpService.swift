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
    
    // Core Request Method (Unified GET, POST, PATCH, DELETE)
    internal func request<T: Codable>(
        _ method: String,
        endpoint: String,
        params: [String: Any]? = nil,
        queryParams: [String: String]? = nil,
        isRetry: Bool = false
    ) async throws -> T {
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
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ApiError(error: "internal_server_error", message: "Invalid response from server.", status: (response as! HTTPURLResponse).statusCode)
        }
        
        if let url = urlComponents.url {
            print("\(httpResponse.statusCode) - \(url)")
        }
        
        if httpResponse.statusCode == 204 {
            return EmptyResponse() as! T
        }
        
        if httpResponse.statusCode == 401 && !isRetry {
            do {
                if let apiService = self as? ApiServiceProtocol {
                    if let refreshToken = UserDefaults.standard.string(forKey: "aegis-refresh-token") {
                        let authResponse = try await apiService.refreshToken(refreshToken: refreshToken)
                        print(authResponse)
                        
                        // Store auth data
                        UserDefaults.standard.set(authResponse.refreshToken, forKey: "aegis-refresh-token")
                        UserDefaults.standard.set(authResponse.accessToken, forKey: "aegis-access-token")
                        
                        return try await self.request(method, endpoint: endpoint, params: params, queryParams: queryParams, isRetry: true)
                    }
                }
            }  catch let error as ApiError {
                print(error)
                throw error
            } catch {
                print(error.localizedDescription)
                throw ApiError(error: "unauthorized", message: "Session expired. Please login again.", status: httpResponse.statusCode)
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
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                print("Decoding error: \(error)")
                throw ApiError(error: "internal_server_error", message: "Failed to parse data from server", status: httpResponse.statusCode)
            }
        } else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                throw ApiError(error: errorJson["error"] as? String, message: errorJson["message"] as? String, status: httpResponse.statusCode)
            } else {
                throw ApiError(error: "internal_server_error", message: "Server error: \(httpResponse.statusCode)", status: httpResponse.statusCode)
            }
        }
    }
}
