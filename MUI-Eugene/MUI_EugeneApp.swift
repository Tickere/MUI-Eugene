//
//  MUI_EugeneApp.swift
//  MUI-Eugene
//
//  Created by Pablo Blumer on 01.10.2025.
//

import SwiftUI
import RealityKit
import RealityKitContent

@main
struct MUI_EugeneApp: App {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    
    @State private var appState = AppState()
    
    init() {
        EugeneComponent.registerComponent()
    }
    
    var body: some SwiftUI.Scene {
        WindowGroup(id: AppState.windowIdentifier) {
            WelcomeView()
                .onChange(of: appState.isImmersive) { _, newValue in
                    if newValue {
                        Task {
                            await openImmersiveSpace(id: AppState.immersiveSpaceIdentifier)
                            dismissWindow(id: AppState.windowIdentifier)
                        }
                    }
                }
                .environment(appState)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        
        ImmersiveSpace(id: AppState.immersiveSpaceIdentifier) {
            LaboratoryView()
                .onChange(of: appState.isImmersive, { _, newValue in
                    if !newValue {
                        Task {
                            await dismissImmersiveSpace()
                            openWindow(id: AppState.windowIdentifier)
                        }
                    }
                })
                .environment(appState)
        }
    }
}
