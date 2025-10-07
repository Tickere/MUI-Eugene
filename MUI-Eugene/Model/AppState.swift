//
//  AppState.swift
//  MUI-Eugene
//
//  Created by Lukman Aščić on 07.10.2025.
//

import Observation
import SwiftUI
import RealityKit
import ARKit

@Observable
class AppState {
    var isImmersive = false
    
    var laboratoryEntity: Entity?

    var placedEugeneRightMachine: Entity?
    var placedEugeneLeftMachine: Entity?
        
    static let immersiveSpaceIdentifier = "lab-space"
    static let windowIdentifier = "start-screen"
    
    var session: ARKitSession = .init()
    var worldTracking: WorldTrackingProvider = .init()
    
    init() {
        Task.detached(priority: .high) {
            do {
                try await self.session.run([self.worldTracking])
            } catch {
                print("\(error.localizedDescription)")
            }
        }
    }
}
