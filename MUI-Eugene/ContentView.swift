import SwiftUI
import RealityKit
import ARKit
import RealityKitContent

struct ContentView: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    var body: some View {
        Text("Opening immersive…")
            .task { _ = await openImmersiveSpace(id: "PlacementSpace") }
    }
}

extension ContentView {
    struct HighlightAllPlanesView: View {
        private let session = ARKitSession()
        private let planes  = PlaneDetectionProvider(alignments: [.horizontal])

        @State private var root = Entity()
        @State private var highlights: [UUID: AnchorEntity] = [:] // planeID -> anchor

        var body: some View {
            RealityView { content in
                content.add(root)
            }
            .task {
                guard PlaneDetectionProvider.isSupported else { return }
                let auth = await session.requestAuthorization(for: [.worldSensing])
                guard auth[.worldSensing] == .allowed else { return }
                try? await session.run([planes])

                for await up in planes.anchorUpdates {
                    let pose = up.anchor.originFromAnchorTransform
                    let id: UUID = up.anchor.id    // <-- use .id

                    switch up.event {
                    case .added:
                        await MainActor.run {
                            let anchor = AnchorEntity()
                            anchor.setTransformMatrix(pose, relativeTo: nil)

                            let hl = ModelEntity(
                                mesh: .generatePlane(width: 0.6, depth: 0.6),
                                materials: [SimpleMaterial(color: .green.withAlphaComponent(0.25), isMetallic: false)]
                            )
                            hl.name = "highlight"
                            anchor.addChild(hl)

                            root.addChild(anchor)
                            highlights[id] = anchor
                        }

                    case .updated:
                        if let anchor = highlights[id] {
                            await MainActor.run {
                                anchor.setTransformMatrix(pose, relativeTo: nil)
                            }
                        }

                    case .removed:
                        // Keep last known pose. Do not remove.
                        break
                    }
                }
            }
        }
    }
}
