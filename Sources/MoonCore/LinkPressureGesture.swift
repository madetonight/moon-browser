import Foundation

public struct LinkPressureGesture {
    public enum Action: Equatable { case insight, preview }
    public static let holdDuration = 0.45
    private var began: TimeInterval?
    private var previewed = false
    public init() {}
    public mutating func begin(at time: TimeInterval) {
        guard began == nil else { return }
        began = time; previewed = false
    }
    public mutating func hold(at time: TimeInterval) -> Action? {
        guard let began, !previewed, time - began >= Self.holdDuration else { return nil }
        previewed = true
        return .preview
    }
    public mutating func end(at time: TimeInterval) -> Action? {
        defer { began = nil; previewed = false }
        guard began != nil, !previewed else { return nil }
        return hold(at: time) ?? .insight
    }
    public mutating func cancel() { began = nil; previewed = false }
}
