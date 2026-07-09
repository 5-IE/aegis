import SwiftUI

struct LoginView: View {
    @ObservedObject var sessionStore: SessionStore
    @StateObject private var viewModel = LoginViewModel()

    var body: some View {
        GeometryReader { proxy in
            let layout = LoginLayout(size: proxy.size)

            if layout.usesCompactLayout {
                compactLayout(layout)
            } else {
                wideLayout(layout)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .ignoresSafeArea()
    }

    private func wideLayout(_ layout: LoginLayout) -> some View {
        HStack(spacing: 0) {
            loginForm
                .frame(width: layout.formWidth, alignment: .leading)
                .frame(width: layout.leftPaneWidth)
                .frame(maxHeight: .infinity, alignment: .center)

            wideLoginHero
                .frame(width: layout.heroWidth)
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func compactLayout(_ layout: LoginLayout) -> some View {
        ScrollView {
            VStack(spacing: 32) {
                loginForm
                    .frame(width: layout.compactFormWidth, alignment: .leading)

                loginHero
                    .frame(maxWidth: .infinity)
                    .frame(height: layout.compactHeroHeight)
            }
            .padding(.horizontal, layout.compactHorizontalPadding)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
        }
    }

    private var loginForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Welcome to Aegis")
                .font(.system(size: 31, weight: .bold))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .padding(.bottom, 12)

            Text("Login to manage your account")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(AegisColors.mutedText)
                .lineLimit(1)
                .padding(.bottom, 28)

            LoginInputField(
                icon: "person",
                placeholder: "Enter your email or phone",
                text: $viewModel.username
            )
            .padding(.bottom, 16)

            LoginSecureField(
                icon: "lock",
                placeholder: "Enter your password",
                text: $viewModel.password
            )
            .onSubmit(signIn)
            .padding(.bottom, 10)

            HStack {
                Spacer()
                Button("Forgot Password?") {
                    viewModel.disabledFeatureMessage = "Password reset is not available yet."
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AegisColors.teal)
            }
            .padding(.bottom, 27)

            Button {
                signIn()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AegisColors.teal)
                        .shadow(color: Color.black.opacity(0.14), radius: 5, x: 0, y: 2)

                    if viewModel.isSigningIn {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Text("SIGN IN")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSubmit)
            .opacity(viewModel.canSubmit ? 1 : 0.58)
            .padding(.bottom, 28)

            HStack(spacing: 4) {
                Spacer()
                Text("Don't have account?")
                    .foregroundStyle(AegisColors.mutedText)
                Button("Sign Up") {
                    viewModel.disabledFeatureMessage = "Account registration is not available yet."
                }
                .buttonStyle(.plain)
                .foregroundStyle(AegisColors.teal)
                .fontWeight(.bold)
                Spacer()
            }
            .font(.system(size: 12, weight: .semibold))

            if let error = sessionStore.authError ?? viewModel.disabledFeatureMessage {
                Text(error)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.75, green: 0.12, blue: 0.12))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func signIn() {
        Task {
            await viewModel.signIn(sessionStore: sessionStore)
        }
    }

    private var loginHero: some View {
        Image("LoginHero")
            .resizable()
            .scaledToFill()
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .clipped()
    }

    private var wideLoginHero: some View {
        Image("LoginHero")
            .resizable()
            .scaledToFill()
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 22,
                    bottomLeadingRadius: 22,
                    style: .continuous
                )
            )
            .clipped()
    }
}

private struct LoginLayout {
    let size: CGSize

    var usesCompactLayout: Bool {
        size.width < 940 || size.height < 600
    }

    var compactHorizontalPadding: CGFloat {
        size.width < 520 ? 24 : 44
    }

    var leftPaneWidth: CGFloat {
        size.width * 0.5
    }

    var heroWidth: CGFloat {
        size.width - leftPaneWidth
    }

    var formWidth: CGFloat {
        min(max(leftPaneWidth * 0.68, 340), 520)
    }

    var compactFormWidth: CGFloat {
        min(460, max(280, size.width - (compactHorizontalPadding * 2)))
    }

    var compactHeroHeight: CGFloat {
        min(420, max(260, size.height * 0.42))
    }
}

private struct LoginInputField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.gray.opacity(0.85))
                .frame(width: 18)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AegisColors.panelBorder, lineWidth: 1)
        }
    }
}

private struct LoginSecureField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.gray.opacity(0.85))
                .frame(width: 18)

            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AegisColors.panelBorder, lineWidth: 1)
        }
    }
}
