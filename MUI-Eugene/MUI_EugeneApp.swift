import SwiftUI

@main
struct MUIEugeneApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .defaultSize(width: 720, height: 600)
        .windowResizability(.contentSize)
    }
}
