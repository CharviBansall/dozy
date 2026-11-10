//
//  Account.swift
//  dozy
//
//  Created by Charvi Bansal on 6/6/26.
//

import Foundation

/// Persists the small amount of account info Apple gives us at sign-in.
/// Apple only returns name/email on the FIRST authorization, so we save it then.
enum Account {
    
    static func save(name: String?, email: String?) -> Void {
        let d = UserDefaults.standard
        if let name, !name.isEmpty { d.set(name, forKey: "account.name") }
        if let email, !email.isEmpty { d.set(email, forKey: "account.email") }
    }

    static var name: String? { UserDefaults.standard.string(forKey: "account.name") }
    static var email: String? { UserDefaults.standard.string(forKey: "account.email") }

    static func saveUserID(_ id: String) {
        UserDefaults.standard.set(id, forKey: "account.userID")
    }
    static var userID: String? { UserDefaults.standard.string(forKey: "account.userID") }
    static var isSignedIn: Bool { userID != nil }

    static func clear() {
        let d = UserDefaults.standard
        d.removeObject(forKey: "account.name")
        d.removeObject(forKey: "account.email")
        d.removeObject(forKey: "account.userID")
    }
}
