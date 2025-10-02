import SwiftUI
import RealityKit
import ARKit
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
    struct HighlightTablesWithGazeAndRotationView: View {
        // Providers
        private let session = ARKitSession()
        private let planes  = PlaneDetectionProvider(alignments: [.horizontal])
        private let world   = WorldTrackingProvider()

        // Scene
        @State private var root = Entity()
        @State private var highlights: [UUID: (anchor: AnchorEntity, quad: ModelEntity)] = [:]
        @State private var activeID: UUID?

        // Materials
        private let baseMat  = SimpleMaterial(color: .green.withAlphaComponent(0.28), isMetallic: false)
        private let focusMat = SimpleMaterial(color: .blue.withAlphaComponent(0.35),  isMetallic: false)

        // De-dup threshold (meters on XZ)
        private let mergeDistance: Float = 0.30

        // Rotation gesture state
        @State private var startPose: simd_float4x4?
        @State private var startAngleRad: Float?

        var body: some View {
            RealityView { content in
                content.add(root)
            }
            .task {
                guard PlaneDetectionProvider.isSupported else { return }
                let auth = await session.requestAuthorization(for: [.worldSensing])
                guard auth[.worldSensing] == .allowed else { return }
                try? await session.run([planes, world])

                // Plane updates with table filter + de-dup
                Task {
                    for await up in planes.anchorUpdates {
                        let id   = up.anchor.id
                        let pose = up.anchor.originFromAnchorTransform

                        switch up.event {
                        case .added, .updated:
                            guard up.anchor.surfaceClassification == .table else { continue }
                            let newPos = centerXZ(of: pose)

                            if let (existingID, existing) = nearestHighlight(to: newPos, within: mergeDistance) {
                                await MainActor.run {
                                    existing.anchor.setTransformMatrix(pose, relativeTo: nil)
                                    highlights[id] = existing
                                    if existingID != id { highlights.removeValue(forKey: existingID) }
                                }
                            } else if let pair = highlights[id] {
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
                                    quad.generateCollisionShapes(recursive: true)
                                    quad.components.set(InputTargetComponent()) // enable gestures

                                    a.addChild(quad)
                                    root.addChild(a)
                                    highlights[id] = (a, quad)
                                }
                            }
                        case .removed:
                            break
                        }
                    }
                }

                // Gaze → choose active table
                Task {
                    while true {
                        if let dev = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
                            let m = dev.originFromAnchorTransform
                            let camPos = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
                            let camFwd = -SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)

                            var best: (id: UUID, dot: Float)? = nil
                            for (id, pair) in highlights {
                                let t  = pair.anchor.transformMatrix(relativeTo: nil)
                                let p  = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
                                let v  = simd_normalize(p - camPos)
                                let d  = simd_dot(camFwd, v)
                                if best == nil || d > best!.dot { best = (id, d) }
                            }
                            await MainActor.run {
                                if let b = best, b.dot >= 0.95 { setActive(b.id) } else { clearActive() }
                            }
                        }
                        try? await Task.sleep(nanoseconds: 33_000_000) // ~30 Hz
                    }
                }
            }
            // Two-finger rotate over the focused quad
            .gesture(
                RotationGesture()
                    .targetedToAnyEntity()
                    .onChanged { value in
                        guard
                            let id = activeID,
                            let pair = highlights[id],
                            value.entity == pair.quad
                        else { return }

                        if startPose == nil || startAngleRad == nil {
                            startPose     = pair.anchor.transformMatrix(relativeTo: nil)
                            startAngleRad = Float(value.gestureValue.radians) // Angle → radians
                        }

                        let current = Float(value.gestureValue.radians)
                        let delta   = current - (startAngleRad ?? 0)
                        let rotated = (startPose ?? matrix_identity_float4x4) * yawRotation(delta)
                        pair.anchor.setTransformMatrix(rotated, relativeTo: nil)
                    }
                    .onEnded { _ in
                        startPose = nil
                        startAngleRad = nil
                    }
            )
        }

        // MARK: - Selection helpers
        private func setActive(_ id: UUID) {
            if activeID == id { return }
            if let prev = activeID, let p = highlights[prev] { p.quad.model?.materials = [baseMat] }
            if let p = highlights[id] { p.quad.model?.materials = [focusMat]; activeID = id }
        }
        private func clearActive() {
            guard let prev = activeID, let p = highlights[prev] else { return }
            p.quad.model?.materials = [baseMat]
            activeID = nil
        }

        // MARK: - De-dup helpers
        private func centerXZ(of m: simd_float4x4) -> SIMD2<Float> { .init(m.columns.3.x, m.columns.3.z) }
        private func nearestHighlight(to p: SIMD2<Float>, within thresh: Float)
            -> (UUID, (anchor: AnchorEntity, quad: ModelEntity))?
        {
            var best: (UUID, (anchor: AnchorEntity, quad: ModelEntity))?
            var bestDist = thresh
            for (id, pair) in highlights {
                let t = pair.anchor.transformMatrix(relativeTo: nil)
                let q = centerXZ(of: t)
                let d = simd_length(p - q)
                if d < bestDist { best = (id, pair); bestDist = d }
            }
            return best
        }

        // MARK: - Math
        private func yawRotation(_ angle: Float) -> simd_float4x4 {
            let c = cos(angle), s = sin(angle)
            return simd_float4x4(
                SIMD4<Float>( c, 0, s, 0),
                SIMD4<Float>( 0, 1, 0, 0),
                SIMD4<Float>(-s, 0, c, 0),
                SIMD4<Float>( 0, 0, 0, 1)
            )
        }
    }
}
