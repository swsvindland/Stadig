import Foundation

/// How a maths problem is meant to be worked. Numeracy is the skill of doing it without help, a
/// topic's problems are written for pen and paper (exact answers, numbers that come out), and the
/// few that need powers or roots to decimal places say a calculator is fine.
public enum MathsTool: String, Sendable, Hashable, CaseIterable {
    case head
    case paper
    case calculator

    /// On a question: "In your head".
    public var label: String {
        switch self {
        case .head: "In your head"
        case .paper: "Pen and paper"
        case .calculator: "Calculator"
        }
    }

    /// After a part's description: "Next: Pythagoras' theorem, with pen and paper".
    public var phrase: String {
        switch self {
        case .head: "in your head"
        case .paper: "with pen and paper"
        case .calculator: "with a calculator"
        }
    }

    /// An SF Symbol for it.
    public var symbol: String {
        switch self {
        case .head: "brain.head.profile"
        case .paper: "pencil"
        case .calculator: "plus.forwardslash.minus"
        }
    }
}
