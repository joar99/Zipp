@MainActor
public final class DependencyContainer {

    public static let shared = DependencyContainer()

    private var registry: [String: Any] = [:]

    private init() {}

    public func register<T>(_ instance: T, for type: T.Type = T.self) {
        registry[String(describing: type)] = instance
    }

    public func resolve<T>() -> T? {
        registry[String(describing: T.self)] as? T
    }

    public func resolveRequired<T>() -> T {
        guard let instance = resolve() as T? else {
            fatalError("Dependency not registered: \(T.self)")
        }
        return instance
    }
}
