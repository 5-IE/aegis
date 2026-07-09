import Foundation
import Combine

@MainActor
class RegisterViewModel: ObservableObject {
    @Published var userId: String = ""
    @Published var isRegistered: Bool = false
    
    var isLoading: Bool = false
    var errorMessage: String? = nil
    
    func registerDevice(store: DataStore) async -> Bool {
        self.isLoading = true
        self.errorMessage = nil
        
        do {
            // generate key pair
            guard let _ = CryptoManager.shared.generateDeviceKeyPair() else {
                self.errorMessage = "Failed to generate Secure Enclave key pair."
                return false
            }
            
            // retrieve public key
            guard let publicKeyBase64 = CryptoManager.shared.getPublicKeyBase64() else {
                self.errorMessage = "Failed to extract Public Key."
                return false
            }
            
            print(publicKeyBase64.count)
            
            _ = try await store.registerDevice(publicKey: publicKeyBase64)
            UserDefaults.standard.set(true, forKey: "aegis-is-registered")
            store.isRegistered = true

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
