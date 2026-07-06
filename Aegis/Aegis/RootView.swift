import SwiftUI

struct RootView: View {
    @State private var isLoggedIn: Bool = false

    var body: some View {
        NavigationStack {
            if isLoggedIn {
                HomeView()
            } else {
                LoginView(isLoggedIn: $isLoggedIn)
            }
        }
    }
}

#Preview {
    RootView()
}
