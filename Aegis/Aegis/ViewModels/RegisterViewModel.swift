import Foundation
import Combine

@MainActor
class RegisterViewModel: ObservableObject {
    @Published var userId: String = ""
    @Published var isRegistered: Bool = false

    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    private let apiService: ApiServiceProtocol

    init(apiService: ApiServiceProtocol = ApiService()) {
        self.apiService = apiService
    }

    func registerDevice() {
        self.isLoading = true
        self.errorMessage = nil

        Task {
            // Generate (or load) the Secure Enclave key and export its raw
            // X9.63 public point as base64.
            guard let publicKeyBase64 = CryptoManager.shared.publicKeyBase64() else {
                self.errorMessage = "Failed to generate or load the device key."
                self.isLoading = false
                return
            }

            do {
                _ = try await apiService.registerDevice(publicKey: publicKeyBase64)
                self.isRegistered = true
            } catch let error as ApiError {
                self.errorMessage = error.message ?? "Device registration failed."
            } catch {
                self.errorMessage = "Device registration failed: \(error.localizedDescription)"
            }
            self.isLoading = false
        }
    }
}
