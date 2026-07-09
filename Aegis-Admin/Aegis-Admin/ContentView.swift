import SwiftUI

struct ContentView: View {
    @StateObject private var sessionStore = SessionStore()

    var body: some View {
        Group {
            switch sessionStore.state {
            case .restoring:
                RestoringSessionView()
            case .signedOut:
                LoginView(sessionStore: sessionStore)
            case let .signedIn(user):
                AdminShellView(sessionStore: sessionStore, user: user)
            }
        }
        .frame(minWidth: 920, minHeight: 640)
        .task {
            await sessionStore.restoreSession()
        }
    }
}

private struct RestoringSessionView: View {
    var body: some View {
        ZStack {
            AdaptiveAppBackground()
            ProgressView()
                .controlSize(.large)
        }
    }
}
