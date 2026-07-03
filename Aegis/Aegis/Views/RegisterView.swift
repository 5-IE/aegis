//
//  RegisterView.swift
//  Aegis
//
//  Created by Steve Agustinus on 03/07/26.
//


import SwiftUI

struct RegisterView: View {
    @StateObject private var viewModel = RegisterViewModel()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .foregroundColor(.blue)
                    
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
                        .foregroundColor(.red)
                        .bold()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top)
                }
                .padding(.top, 40)
                
                if viewModel.isRegistered {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 48))
                        
                        Text("Device Successfully Bound!")
                            .font(.headline)
                        
                        Text("Your hardware key is securely registered with the server.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                    
                } else {
                    VStack(spacing: 16) {
                        Button(action: {
                            viewModel.registerDevice()
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
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
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
}


#Preview {
    RegisterView()
}
