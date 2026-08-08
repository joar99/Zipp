@MainActor
public protocol CoordinatorProtocol: AnyObject {
    var childCoordinators: [CoordinatorProtocol] { get set }
}

@MainActor
public extension CoordinatorProtocol {
    func append(child: CoordinatorProtocol) {
        childCoordinators.append(child)
    }

    func remove(child: CoordinatorProtocol) {
        childCoordinators.removeAll { $0 === child }
    }
}
