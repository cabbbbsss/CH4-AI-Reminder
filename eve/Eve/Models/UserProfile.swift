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

    var homeLocation: String?

    var workLocation: String?

    var reminderStyle: String

    var createdAt: Date

    init(
        homeLocation: String? = nil,
        workLocation: String? = nil,
        reminderStyle: String = "Adaptive",
        createdAt: Date = .now
    ) {

        self.homeLocation = homeLocation
        self.workLocation = workLocation
        self.reminderStyle = reminderStyle
        self.createdAt = createdAt

    }

}
