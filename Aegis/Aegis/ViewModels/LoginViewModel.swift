//
//  LoginViewModel.swift
//  Aegis
//
//  Created by Steve Agustinus on 06/07/26.
//


import Foundation
import Combine

@MainActor
class LoginViewModel: ObservableObject {
    @Published var username = ""
    @Published var password = ""
    
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    
    func login(store: DataStore) async -> Bool {
        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter both username and password."
            return false
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            _ = try await store.login(username: username, password: password)

            isLoading = false
            return true
        } catch let error as ApiError {
            self.errorMessage = error.message
            isLoading = false
            return false
        } catch {
            self.errorMessage = "Failed to connect to the server."
            isLoading = false
            return false
        }
    }
}
