import SwiftUI
import RealityKit   // needed for registerComponent()
import RealityKitContent

@main
struct EugenePlacementApp: App {
    init() {
        // Register before any RealityKit asset loads.
        EugeneComponent.registerComponent()
    }

    var body: some SwiftUI.Scene {   // disambiguate from RealityKit.Scene
        WindowGroup { ContentView() }
        ImmersiveSpace(id: "PlacementSpace") { ContentView.HighlightPlaceConfirmView() }
    }
}
