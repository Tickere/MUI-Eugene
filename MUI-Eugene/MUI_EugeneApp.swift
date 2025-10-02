import SwiftUI

@main
struct EugenePlacementApp: App {
    var body: some Scene {
        // Small window just to trigger immersive space
        WindowGroup {
            ContentView()
        }

        // Immersive space where we detect planes and place the sphere
        ImmersiveSpace(id: "PlacementSpace") {
            ContentView.AutoPlaceSphereView()
        }
    }
}
