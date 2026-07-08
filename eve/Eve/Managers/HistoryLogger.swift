//
//  HistoryLogger.swift
//  Eve
//
//  Created by cabsss on 06/07/26.
//

import Foundation
import SwiftData

/// The single place where timeline entries are written.
/// Services observe the world; this manager records what happened.
final class HistoryLogger {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func log(
        _ type: HistoryItemType,
        title: String,
        detail: String = ""
    ) throws {

        let item = HistoryItem(
            type: type,
            title: title,
            detail: detail
        )

        context.insert(item)

        try context.save()

    }

}
