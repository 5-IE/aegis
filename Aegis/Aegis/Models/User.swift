//
//  File.swift
//  Aegis
//
//  Created by Steve Agustinus on 06/07/26.
//

import Foundation

struct User: Codable {
    let id: Int
    let username: String
    let role: String
    let session: String
    let firstName: String
    let lastName: String
    let email: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case role
        case session
        case firstName = "first_name"
        case lastName = "last_name"
        case email
    }
}
