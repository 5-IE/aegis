//
//  ApiResponse.swift
//  eltar-mobile
//
//  Created by Steve Agustinus on 21/03/26.
//

import Foundation
import SwiftUI


struct ApiResponse<T: Codable>: Codable {
    let message: String?
    let data: T?
}

struct ApiError: Error {
    let message: String?
}

struct LoginData: Codable {
    let idUser: Int
    let name: String
    let userType: Int
    let key: String
    
    enum CodingKeys: String, CodingKey {
        case idUser = "id_user"
        case name = "name"
        case userType = "user_type"
        case key = "key"
    }
}
