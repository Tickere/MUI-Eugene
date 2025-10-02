import SwiftUI
import RealityKit
import ARKit
import RealityKitContent

struct ContentView: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        VStack {
            Text("Opening immersive placement…")
        }
        .task {
            // Open immersive space automatically
            _ = await openImmersiveSpace(id: "PlacementSpace")
        }
    }
}

// MARK: - Immersive placement view
extension ContentView {
    struct AutoPlaceSphereView: View {
        // ARKit
        private let session = ARKitSession()
        private let planes  = PlaneDetectionProvider(alignments: [.horizontal])

        // Scene state
        @State private var anchor = AnchorEntity()
        @State private var sphere: ModelEntity?
        @State private var debugPlane: ModelEntity?
        @State private var placed = false

        private let r: Float = 0.06

        var body: some View {
            RealityView { content in
                content.add(anchor)

                // Debug plane
                let dbg = ModelEntity(
                    mesh: .generatePlane(width: 0.6, depth: 0.6),
                    materials: [SimpleMaterial(color: .green.withAlphaComponent(0.25), isMetallic: false)]
                )
                dbg.isEnabled = false
                anchor.addChild(dbg)
                debugPlane = dbg

                // Sphere, hidden until plane is detected
                let ball = ModelEntity(
                    mesh: .generateSphere(radius: r),
                    materials: [SimpleMaterial(color: .blue, isMetallic: false)]
                )
                ball.position = [0, r, 0]
                ball.isEnabled = false
                anchor.addChild(ball)
                sphere = ball
            }
            .task {
                // 1) Supported?
                guard PlaneDetectionProvider.isSupported else { return }

                // 2) Ask for permission
                let auth = await session.requestAuthorization(for: [.worldSensing])
                guard auth[.worldSensing] == .allowed else { return }

                // 3) Run provider
                try? await session.run([planes])

                // 4) Handle updates
                for await update in planes.anchorUpdates {
                    switch update.event {
                    case .added where !placed:
                        let pose = update.anchor.originFromAnchorTransform
                        await MainActor.run {
                            anchor.setTransformMatrix(pose, relativeTo: nil)
                            debugPlane?.isEnabled = true
                            sphere?.isEnabled = true
                            placed = true
                        }
                    case .updated where placed:
                        let pose = update.anchor.originFromAnchorTransform
                        await MainActor.run {
                            anchor.setTransformMatrix(pose, relativeTo: nil)
                        }
                    default:
                        break
                    }
                }
            }
        }
    }
}
