//
//  RegisterView.swift
//  Aegis
//
//  Created by Steve Agustinus on 03/07/26.
//


import SwiftUI

struct RegisterView: View {
    @Environment(DataStore.self) private var dataStore
    @StateObject private var viewModel = RegisterViewModel()

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundColor(Theme.primary)

                Text("Secure Device Binding")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("This process links this physical iPhone to your Academy Tracker account.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.top)

                Text("This is only one time process. You are prohibited to bind this device to account you don't belong to.")
                    .font(.subheadline)
                    .foregroundColor(Theme.leave)
                    .bold()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.top)
            }
            .padding(.top, 40)

            if viewModel.isRegistered {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.onTime)
                        .font(.system(size: 48))

                    Text("Device Successfully Bound!")
                        .font(.headline)

                    Text("Your hardware key is securely registered with the server.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Continue") {
                        dataStore.isRegistered = true
                        UserDefaults.standard.set(true, forKey: "aegis-device-registered")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Theme.onTimeBackground)
                .cornerRadius(12)

            } else {
                VStack(spacing: 16) {
                    Button(action: {
                        Task { await viewModel.registerDevice(store: dataStore) }
                    }) {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Register Device")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.primary)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(Theme.leave)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal)
            }

            Spacer()
        }
        .navigationTitle("Registration")
        .navigationBarTitleDisplayMode(.inline)
        .padding()
    }
}


#Preview {
    NavigationStack { RegisterView().environment(DataStore(apiService: ApiService())) }
}
