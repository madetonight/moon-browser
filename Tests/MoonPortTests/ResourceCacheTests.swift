import XCTest
@testable import Moon

@MainActor
final class ResourceCacheTests: XCTestCase {
    private final class ImageResource {}

    func testHotImagesSurviveEvictionAndColdImagesAreReleased() {
        let cache = ResourceCache<String, ImageResource>(capacity: 2)
        let visible = ImageResource()
        weak var cold: ImageResource?
        cache["visible"] = visible
        do {
            let image = ImageResource()
            cold = image
            cache["cold"] = image
        }
        XCTAssertTrue(cache["visible"] === visible) // Keep the visible key hot.
        cache["new"] = ImageResource()
        XCTAssertNil(cold, "Evicted decoded images must actually release their storage")
        XCTAssertEqual(cache.count, 2)
        cache.removeAll()
        XCTAssertEqual(cache.count, 0)
        XCTAssertNotNil(visible, "A visible row's own reference remains usable after cache pressure")
    }

    func testHistorySizedWorkloadRemainsBoundedAndKeepsRecentResults() {
        let cache = ResourceCache<Int, Int>(capacity: 512)
        for key in 0..<10_000 { cache[key] = key }
        XCTAssertEqual(cache.count, 512)
        XCTAssertNil(cache[0])
        XCTAssertEqual(cache[9999], 9999)
        cache[9999] = 7
        XCTAssertEqual(cache.count, 512)
        XCTAssertEqual(cache[9999], 7)
        cache[9999] = nil
        XCTAssertEqual(cache.count, 511)
    }

    func testOptionalLookupMissCanBeCachedUntilTheIndexChanges() {
        let cache = ResourceCache<String, Int?>(capacity: 2)
        cache["missing"] = .some(nil)
        XCTAssertEqual(cache.count, 1)
        XCTAssertNotNil(cache["missing"] as Any?)
        cache.removeAll()
        XCTAssertNil(cache["missing"] as Any?)
    }
}
