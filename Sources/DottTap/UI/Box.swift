import Combine

/// View-local state holder. Stands in for `@State`, whose macro plugin only ships with
/// full Xcode; this builds with the command-line tools alone.
final class Box<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}
