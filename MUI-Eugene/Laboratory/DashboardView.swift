//
//  DashboardView.swift
//  MUI-Eugene
//
//  Created by Lukman Aščić on 07.10.2025.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        VStack {
            if appState.placedEugeneLeftMachine != nil || appState.placedEugeneRightMachine != nil {
                createGridExplanationView(left: appState.placedEugeneLeftMachine, right: appState.placedEugeneRightMachine)
                    .frame(width: 800, height: 600)
                    .padding()
                    .glassBackgroundEffect()
            } else {
                tipView
                    .frame(maxWidth: 400)
                    .padding()
                    .glassBackgroundEffect(in: .rect(cornerRadius: 18))
            }
            
            if appState.placedEugeneLeftMachine != nil && appState.placedEugeneRightMachine != nil {
                completeButton
                    .frame(maxWidth: 400)
                    .padding()
                    .glassBackgroundEffect(in: .rect(cornerRadius: 18))
            }
        }
    }
    
    private func createGridExplanationView(left leftEugeneEntity: Entity?, right rightEugeneEntity: Entity?) -> some View {
        VStack {
            Text("TODO: show the grid view based on the two eugene components ")
            
            HStack {
                if let leftEugeneComponent = leftEugeneEntity?.components[EugeneComponent.self] {
                    Text("do something with \(leftEugeneComponent.code)")
                }
                
                if let rightEugeneComponent = rightEugeneEntity?.components[EugeneComponent.self] {
                    Text("do something with \(rightEugeneComponent.code)")
                }
            }
        }
    }
    
    private var tipView: some View {
        VStack {
            Text("catch one of those eugenes and place one in each machine")
        }
    }
    
    private var completeButton: some View {
        Button {
            // TODO: Do some logic based on EugeneComponent's code and generation on
            // appState.placedEugeneLeftMachine and appState.placedEugeneRightMachine
            //
            // Then place a new eugene entity based on the following starter code
            guard let leftEugeneComponent = appState.placedEugeneLeftMachine?.components[EugeneComponent.self],
                  let rightEugeneComponent = appState.placedEugeneRightMachine?.components[EugeneComponent.self] else {
                print("not yet placed all")
                return
            }

            print("placing a new entity on the generation anchor")
            if let machineGenerationEntity = appState.laboratoryEntity?.findEntity(named: "generation_anchor"),
                let newEugene = try? Entity.load(named: "mySpecialEgene", in: realityKitContentBundle) {
                newEugene.position = machineGenerationEntity.position // Position it where the generation "null object" is placed
                
                // TODO: Generate specific code and generation based on placed eugenes
                
                let newCode = "asdfasdf"
                let newGeneration: Int = 2
                
                let newEugeneComponent = EugeneComponent(code: newCode, generation: newGeneration)
                newEugene.components.set(newEugeneComponent)
                
                if let uiAnchor = newEugene.findEntity(named: "eugene_ui_anchor") {
                    let viewAttachmentComponent = ViewAttachmentComponent(rootView: EugeneLabelView(codeTitle: newCode, generation: newGeneration))
                    uiAnchor.components.set(viewAttachmentComponent)
                }
                
                var manipulationComponent = ManipulationComponent()
                manipulationComponent.releaseBehavior = .reset
                newEugene.components.set(manipulationComponent)
                
                // TODO: Start the animation / timeline
                
                appState.laboratoryEntity?.addChild(newEugene)
            }
        } label: {
            HStack {
                Text("Complete".uppercased())
                    .font(.title)
                    .fontWeight(.bold)
            }
        }
    }
}

#Preview {
    DashboardView()
        .environment(AppState())
}
