import RealityKit

// Ensure you register this component in your app’s delegate using:
// EugeneComponent.registerComponent()
public struct EugeneComponent: Component, Codable {
    // This is an example of adding a variable to the component.
    public var code: String = ""
    public var generation: Int = 1
    
    public init(code: String = "", generation: Int = 1) {
        self.code = code
        self.generation = generation
    }
}
