//
//  LaboratoryView.swift
//  MUI-Eugene
//
//  Created by Lukman Aščić on 07.10.2025.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct LaboratoryView: View {
    @Environment(AppState.self) private var appState
    
    @State private var machineRightCollisionEvent: EventSubscription?
    @State private var machineLeftCollisionEvent: EventSubscription?
    
    let anchoringComponent = AnchoringComponent.init(.plane(.horizontal, classification: .table, minimumBounds: .zero), trackingMode: .once)
        
    var body: some View {
        RealityView { content in
            if let labEntity = try? await Entity(named: "Laboratory", in: realityKitContentBundle) {
                if let uiAnchor = labEntity.findEntity(named: "machine_ui_anchor") {
                    let labAttachmentComponent = ViewAttachmentComponent(rootView: DashboardView().environment(appState))
                    uiAnchor.components.set(labAttachmentComponent)
                }
                
                labEntity.findEntity(named: "Root")?.children.first?.children.forEach { entity in
                    print(entity.name)
                    if let eugeneComponent = entity.components[EugeneComponent.self] {
                        print("has eugene component")
                        var manipulationComponent = ManipulationComponent()
                        manipulationComponent.releaseBehavior = .reset
                        entity.components.set(manipulationComponent)
                        
                        let viewAttachmentComponent = ViewAttachmentComponent(rootView: EugeneLabelView(codeTitle: eugeneComponent.code, generation: eugeneComponent.generation))
                        entity.findEntity(named: "eugene_ui_anchor")?.components.set(viewAttachmentComponent)
                    }
                }
                
                if let leftMachineEntity = labEntity.findEntity(named: "Machine_1"), let leftPlacementAnchor = labEntity.findEntity(named: "machine_1_anchor") {
                    machineLeftCollisionEvent = content.subscribe(to: CollisionEvents.Began.self, on: leftMachineEntity, { event in
                        print(event.entityA.name, event.entityB.name)
                        event.entityB.components[InputTargetComponent.self]?.isEnabled = false // Disable interaction
                        event.entityB.components[ManipulationComponent.self]?.releaseBehavior = .stay // Do not reset anymore.
                        Entity.animate(.smooth) {
                            event.entityB.position = leftPlacementAnchor.position
                        }
                        print("place it on ", leftPlacementAnchor.position)
                    })
                }
                
                if let rightMachineEntity = labEntity.findEntity(named: "Machine_2"), let rightPlacementAnchor = labEntity.findEntity(named: "machine_2_anchor") {
                    machineRightCollisionEvent = content.subscribe(to: CollisionEvents.Began.self, on: rightMachineEntity, { event in
                        // TODO: Same as machine 1 above
                        print(event.entityA.name, event.entityB.name)
                    })
                }
                
                labEntity.findEntity(named: "Root")?.anchor?.anchoring = anchoringComponent

                appState.laboratoryEntity = labEntity
                content.add(labEntity)
            }
        }
    }
}

#Preview(immersionStyle: .mixed) {
    LaboratoryView()
        .environment(AppState())
}
