import Foundation
import Combine

@MainActor
class RegisterViewModel: ObservableObject {
    @Published var userId: String = ""
    @Published var isRegistered: Bool = false
    
    var isLoading: Bool = false
    var errorMessage: String? = nil
    
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
                
                print(publicKeyBase64)
            }
        }
    }
}
