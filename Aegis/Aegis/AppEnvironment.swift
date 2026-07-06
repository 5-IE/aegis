//
//  AppEnvironment.swift
//  Aegis
//  test
//
//  Created by Steve Agustinus on 03/07/26.
//


import Foundation

enum AppEnvironment {
    case development
    case production
    
    static let current: AppEnvironment = .development
    
    var baseURL: String {
        switch self {
        case .development:
            return "http://192.168.1.10:3000"
        case .production:
            return "http://10.60.57.161:3000"
        }
    }
}
