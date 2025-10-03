import SwiftUI

@main
struct EugenePlacementApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
        ImmersiveSpace(id: "PlacementSpace") { ContentView.HighlightPlaceConfirmView() }
    }
}
