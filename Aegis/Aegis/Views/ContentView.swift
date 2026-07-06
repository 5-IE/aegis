//
//  ContentView.swift
//  Aegis
//
//  Created by William Antoline's Workspace on 01/07/26.
//

import SwiftUI

struct ContentView: View {
    @State private var dataStore = DataStore(apiService: ApiService())

    var body: some View {
        NavigationStack {
            if dataStore.isLoggedIn {
                if dataStore.isRegistered {
                    HomeView()
                } else {
                    RegisterView()
                }
            } else {
                LoginView()
            }
        }
        .environment(dataStore)
        .task {
            await dataStore.loadInitialData()
        }
        .animation(.easeInOut, value: dataStore.isLoggedIn)
        .animation(.easeInOut, value: dataStore.isRegistered)
    }
}

#Preview {
    ContentView()
}
