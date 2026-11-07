/// A bounded hot cache with constant-time lookup, promotion and eviction.
/// Eviction releases the cache's reference; a visible view keeps its image.
@MainActor
final class ResourceCache<Key: Hashable, Value> {
    private final class Entry {
        let key: Key
        var value: Value
        weak var previous: Entry?
        var next: Entry?
        init(key: Key, value: Value) { self.key = key; self.value = value }
    }
    let capacity: Int
    private var entries: [Key: Entry] = [:]
    private var first: Entry?
    private var last: Entry?
    var count: Int { entries.count }

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    subscript(key: Key) -> Value? {
        get {
            guard let entry = entries[key] else { return nil }
            unlink(entry)
            prepend(entry)
            return entry.value
        }
        set {
            guard let value = newValue else {
                if let entry = entries.removeValue(forKey: key) { unlink(entry) }
                return
            }
            if let entry = entries[key] {
                entry.value = value
                unlink(entry)
                prepend(entry)
            } else {
                let entry = Entry(key: key, value: value)
                entries[key] = entry
                prepend(entry)
                if entries.count > capacity, let oldest = last {
                    unlink(oldest)
                    entries[oldest.key] = nil
                }
            }
        }
    }

    func removeAll() {
        first = nil
        last = nil
        entries.removeAll(keepingCapacity: false)
    }

    private func unlink(_ entry: Entry) {
        entry.previous?.next = entry.next
        entry.next?.previous = entry.previous
        if first === entry { first = entry.next }
        if last === entry { last = entry.previous }
        entry.previous = nil
        entry.next = nil
    }

    private func prepend(_ entry: Entry) {
        entry.next = first
        first?.previous = entry
        first = entry
        if last == nil { last = entry }
    }
}
