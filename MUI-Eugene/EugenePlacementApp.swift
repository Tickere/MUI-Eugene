import SwiftUI
import RealityKit
import RealityKitContent

@main
struct EugenePlacementApp: App {
    init() {
        EugeneComponent.registerComponent() // register before any asset loads
    }

    var body: some SwiftUI.Scene {
        WindowGroup { ContentView() }
        ImmersiveSpace(id: "PlacementSpace") { ContentView.HighlightPlaceConfirmView() }
    }
}
