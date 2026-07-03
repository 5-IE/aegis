import Foundation
import Combine

@MainActor
class RegisterViewModel: ObservableObject {
    @Published var userId: String = ""
    @Published var isLoading: Bool = false
    @Published var isRegistered: Bool = false
    @Published var errorMessage: String? = nil
    
    private let apiService = ApiService()
    
    func registerDevice() {
//        guard !userId.trimmingCharacters(in: .whitespaces).isEmpty else {
//            self.errorMessage = "Please enter a User ID."
//            return
//        }
        
        self.isLoading = true
        self.errorMessage = nil
        
        Task {
            do {
                // generate key pair
                guard let _ = CryptoManager.shared.generateDeviceKeyPair() else {
                    self.errorMessage = "Failed to generate Secure Enclave key pair."
                    return
                }
                
                // retrieve public key
                guard let publicKeyBase64 = CryptoManager.shared.getPublicKeyBase64() else {
                    self.errorMessage = "Failed to extract Public Key."
                    return
                }
                
                // send to server via ApiService
                do {
                    let params = [
                        "userId": userId,
                        "publicKeyBase64": publicKeyBase64
                    ]
                    let response = try await apiService.registerDevice(params: params)
                    
                    if response.message == "SUCCESS" {
                        await MainActor.run {
                            self.isRegistered = true
                            self.isLoading = false
                        }
                    } else {
                        errorMessage = response.message
                    }
                } catch {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}
