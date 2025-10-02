import SwiftUI
import RealityKit
import ARKit
import RealityKitContent
import simd
import QuartzCore

struct ContentView: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    var body: some View {
        Text("Opening immersive…")
            .task { _ = await openImmersiveSpace(id: "PlacementSpace") }
    }
}

extension ContentView {
    struct HighlightTablesWithGazeView: View {
        // Providers
        private let session = ARKitSession()
        private let planes  = PlaneDetectionProvider(alignments: [.horizontal])
        private let world   = WorldTrackingProvider()

        // Scene graph
        @State private var root = Entity()
        @State private var highlights: [UUID: (anchor: AnchorEntity, quad: ModelEntity)] = [:]
        @State private var activeID: UUID?

        // Materials
        private let baseMat  = SimpleMaterial(color: .green.withAlphaComponent(0.28), isMetallic: false)
        private let focusMat = SimpleMaterial(color: .blue.withAlphaComponent(0.35),  isMetallic: false)

        var body: some View {
            RealityView { content in
                content.add(root)
            }
            .task {
                // Capability + permission
                guard PlaneDetectionProvider.isSupported else { return }
                let auth = await session.requestAuthorization(for: [.worldSensing])
                guard auth[.worldSensing] == .allowed else { return }

                // Start providers (async throws)
                try? await session.run([planes, world])

                // Plane updates
                Task {
                    for await up in planes.anchorUpdates {
                        let id   = up.anchor.id
                        let pose = up.anchor.originFromAnchorTransform

                        switch up.event {
                        case .added, .updated:
                            // visionOS 26+: use surfaceClassification
                            guard up.anchor.surfaceClassification == .table else { continue }

                            if let pair = highlights[id] {
                                await MainActor.run { pair.anchor.setTransformMatrix(pose, relativeTo: nil) }
                            } else {
                                await MainActor.run {
                                    let a = AnchorEntity()
                                    a.setTransformMatrix(pose, relativeTo: nil)

                                    let quad = ModelEntity(
                                        mesh: .generatePlane(width: 0.8, depth: 0.8),
                                        materials: [baseMat]
                                    )
                                    quad.name = "tableHighlight"
                                    a.addChild(quad)

                                    root.addChild(a)
                                    highlights[id] = (a, quad)
                                }
                            }

                        case .removed:
                            // Keep last pose so the highlight persists off-camera.
                            break
                        }
                    }
                }

                // Pose polling for “look-at” selection
                Task {
                    while true {
                        // Synchronous, non-throwing
                        if let dev = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
                            let m = dev.originFromAnchorTransform
                            let camPos = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
                            let camFwd = -SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)

                            var best: (id: UUID, dot: Float)? = nil
                            for (id, pair) in highlights {
                                let aT = pair.anchor.transformMatrix(relativeTo: nil)
                                let pos = SIMD3<Float>(aT.columns.3.x, aT.columns.3.y, aT.columns.3.z)
                                let toPlane = simd_normalize(pos - camPos)
                                let dot = simd_dot(camFwd, toPlane)
                                if best == nil || dot > best!.dot { best = (id, dot) }
                            }

                            await MainActor.run {
                                if let b = best, b.dot >= 0.95 { setActive(b.id) } else { clearActive() }
                            }
                        }
                        try? await Task.sleep(nanoseconds: 33_000_000) // ~30 Hz
                    }
                }
            }
        }

        // MARK: - Helpers
        private func setActive(_ id: UUID) {
            if activeID == id { return }
            if let prev = activeID, let pair = highlights[prev] { pair.quad.model?.materials = [baseMat] }
            if let pair = highlights[id] { pair.quad.model?.materials = [focusMat]; activeID = id }
        }
        private func clearActive() {
            guard let prev = activeID, let pair = highlights[prev] else { return }
            pair.quad.model?.materials = [baseMat]
            activeID = nil
        }
    }
}
