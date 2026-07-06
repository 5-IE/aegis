//
//  LoginView.swift
//  Aegis
//
//  Created by Steve Agustinus on 06/07/26.
//

import SwiftUI

struct LoginView: View {
    @Environment(DataStore.self) private var dataStore
    @StateObject var viewModel = LoginViewModel()

    var body: some View {
        ZStack {
            Theme.screenBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 40)

                // Logo
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color(red: 0.80, green: 0.85, blue: 0.90))
                        .frame(width: 120, height: 120)
                    Image(systemName: "shield.lefthalf.filled")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .foregroundColor(Theme.primary)
                }
                .padding(.bottom, 40)

                // Card
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome Back!")
                            .font(.title2.bold())
                            .foregroundColor(Theme.textPrimary)
                        Text("Please enter your credentials")
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                    }

                    IconTextField(icon: "envelope", placeholder: "Enter your email or phone", text: $viewModel.username)
                    IconTextField(icon: "lock", placeholder: "Enter your password", text: $viewModel.password, isSecure: true)

                    HStack {
                        Spacer()
                        Button("Forgot Password?") {}
                            .font(.footnote)
                            .foregroundColor(Theme.textSecondary)
                    }

                    PrimaryButton(title: "SIGN IN") {
                        Task {
                            let success = await viewModel.login(store: dataStore)
                            if success {
                                dataStore.isLoggedIn = true
                            }
                        }
                    }
                    .padding(.top, 4)

                    HStack {
                        VStack { Divider() }
                        Text("OR")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                        VStack { Divider() }
                    }

                    SecondaryButton(title: "Continue with SSO") {}
                }
                .padding(24)
                .background(Theme.cardBackground)
                .cornerRadius(Theme.cornerRadius)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
                .padding(.horizontal, 20)

                Spacer(minLength: 24)
            }
        }
    }
}

#Preview {
    LoginView()
}
