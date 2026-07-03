//
//  ApiService.swift
//  eltar-mobile
//
//  Created by Steve Agustinus on 21/03/26.
//


class ApiService: HttpService {
    
    // Auth (example)
//    func login(params: [String: Any]) async throws -> ApiResponse<LoginData> {
//        try await request("POST", endpoint: "/login", params: params)
//    }
    func registerDevice(params: [String: Any]) async throws -> ApiResponse<EmptyResponse> {
            try await request("POST", endpoint: "/register-device", params: params)
        }
    
    
    // Transactions (example only)
//    func getTransaction(params: [String: String]) async throws -> ApiResponse<[Transaction]> {
//        try await request("GET", endpoint: "/transaction", queryParams: params)
//    }
//    func addTransaction(params: [String: Any]) async throws -> ApiResponse<EmptyResponse> {
//        try await request("POST", endpoint: "/transaction", params: params)
//    }
//    func editTransaction(params: [String: Any]) async throws -> ApiResponse<EmptyResponse> {
//        try await request("PATCH", endpoint: "/transaction", params: params)
//    }
//    func addTransferTransaction(params: [String: Any]) async throws -> ApiResponse<EmptyResponse> {
//        try await request("POST", endpoint: "/transfer_transaction", params: params)
//    }
}

// Dummy struct for 204 No Content or empty data
struct EmptyResponse: Codable {}
