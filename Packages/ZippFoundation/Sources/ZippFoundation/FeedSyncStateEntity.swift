import Foundation
import SwiftData

/// Bookkeeping for one upstream feed, so a refresh can tell whether there is
/// anything worth downloading.
@Model
public final class FeedSyncStateEntity {

    @Attribute(.unique) public var feedID: String
    /// The entity tag the archive carried the last time we read it.
    public var entityTag: String?
    /// When we last asked the server, whether or not anything had changed.
    public var lastCheckedAt: Date
    /// When the stored stops last actually changed.
    public var lastUpdatedAt: Date?

    public init(
        feedID: String,
        entityTag: String? = nil,
        lastCheckedAt: Date = .distantPast,
        lastUpdatedAt: Date? = nil
    ) {
        self.feedID = feedID
        self.entityTag = entityTag
        self.lastCheckedAt = lastCheckedAt
        self.lastUpdatedAt = lastUpdatedAt
    }
}
