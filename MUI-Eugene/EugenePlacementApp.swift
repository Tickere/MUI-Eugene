import SwiftUI
import RealityKit
import RealityKitContent

@main
struct EugenePlacementApp: App {
    init() {
        // Register custom component before any asset loads.
        EugeneComponent.registerComponent()
    }

    var body: some SwiftUI.Scene {
        WindowGroup { ContentView() }
        ImmersiveSpace(id: "PlacementSpace") { ContentView.HighlightPlaceConfirmView() }
    }
}
