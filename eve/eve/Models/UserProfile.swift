//
//  UserProfile.swift
//  Eve
//
//  Created by cabsss on 05/07/26.
//

import Foundation
import SwiftData

@Model //SwiftData only stores objects marked with @Model
final class UserProfile {

    /// What the user asks EVE to call them. Empty until they set it in Settings.
    var name: String

    var createdAt: Date

    init(
        name: String = "",
        createdAt: Date = .now
    ) {

        self.name = name
        self.createdAt = createdAt

    }

}

extension UserProfile {

    /// Returns the app's single profile, creating and inserting it on first use.
    /// The app only ever has one user, so we treat UserProfile as a singleton.
    static func current(in context: ModelContext) -> UserProfile {

        if let existing = try? context.fetch(FetchDescriptor<UserProfile>()).first {
            return existing
        }

        let profile = UserProfile()
        context.insert(profile)
        return profile
    }

}
