import Foundation
import SwiftData
import ZippFoundation

/// Builds the app's SwiftData stack.
///
/// Deliberately not tied to a SwiftUI view: the container is created here and
/// handed to repositories, which own every read and write.
public enum ZippModelContainer {

    public static let schema = Schema([
        StopPlaceEntity.self,
        FeedSyncStateEntity.self,
    ])

    public static func make(storedInMemoryOnly: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: storedInMemoryOnly
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
