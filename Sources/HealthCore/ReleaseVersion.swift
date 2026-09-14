import Foundation

/// A numeric release version used for comparing an installed app with a GitHub tag.
/// Stable tags such as `v1.2.0` are accepted; prerelease labels are deliberately
/// rejected so an accidentally published beta cannot be offered as a stable update.
public struct ReleaseVersion: Comparable, CustomStringConvertible, Sendable {
    private let components: [Int]

    public init?(_ value: String) {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.first == "v" || candidate.first == "V" {
            candidate.removeFirst()
        }
        let pieces = candidate.split(separator: ".", omittingEmptySubsequences: false)
        guard !pieces.isEmpty,
              pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let parsed = try? pieces.map({ piece -> Int in
                  guard let number = Int(piece) else { throw ParseError.invalidComponent }
                  return number
              }) else { return nil }
        components = parsed
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        compare(lhs.components, rhs.components) == 0
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        compare(lhs.components, rhs.components) < 0
    }

    private static func compare(_ lhs: [Int], _ rhs: [Int]) -> Int {
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left < right ? -1 : 1 }
        }
        return 0
    }

    private enum ParseError: Error { case invalidComponent }
}
