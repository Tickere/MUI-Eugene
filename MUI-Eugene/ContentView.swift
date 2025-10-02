import SwiftUI
import RealityKit
import ARKit
import simd
import QuartzCore

struct ContentView: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    var body: some View {
        Text("Opening immersive…").task { _ = await openImmersiveSpace(id: "PlacementSpace") }
    }
}

extension ContentView {
    struct HighlightTablesWithGazeRotateNudgeView: View {
        // Providers
        private let session = ARKitSession()
        private let planes  = PlaneDetectionProvider(alignments: [.horizontal])
        private let world   = WorldTrackingProvider()

        // Scene
        @State private var root = Entity()

        struct PlaneItem {
            var anchor: AnchorEntity
            var quad: ModelEntity
            var locked: Bool
        }
        @State private var items: [UUID: PlaneItem] = [:]
        @State private var activeID: UUID?

        // Materials
        private let baseMat  = SimpleMaterial(color: .green.withAlphaComponent(0.0), isMetallic: false) // invisible
        private let focusMat = SimpleMaterial(color: .blue.withAlphaComponent(0.35),  isMetallic: false)

        // De-dup
        private let mergeDistance: Float = 0.30

        // Rotation
        @State private var startPoseRot: simd_float4x4?
        @State private var startAngleRad: Float?

        // Nudge
        @State private var isDragging = false
        @State private var startPoseMove: simd_float4x4?
        @State private var lastHitLocal: SIMD3<Float>?
        private let stepClamp: Float = 0.03
        private let quant: Float     = 0.01

        var body: some View {
            RealityView { content in
                content.add(root)
            }
            .task {
                guard PlaneDetectionProvider.isSupported else { return }
                let auth = await session.requestAuthorization(for: [.worldSensing])
                guard auth[.worldSensing] == .allowed else { return }
                try? await session.run([planes, world])

                // Plane updates (skip locked)
                Task {
                    for await up in planes.anchorUpdates {
                        let pid = up.anchor.id
                        let pose = up.anchor.originFromAnchorTransform

                        switch up.event {
                        case .added, .updated:
                            guard up.anchor.surfaceClassification == .table else { continue }

                            if let item = items[pid], item.locked { continue }

                            let newPos = centerXZ(of: pose)
                            if let (existingID, existing) = nearestItem(to: newPos, within: mergeDistance) {
                                await MainActor.run {
                                    if !existing.locked { existing.anchor.setTransformMatrix(pose, relativeTo: nil) }
                                    items[pid] = existing
                                    if existingID != pid { items.removeValue(forKey: existingID) }
                                }
                            } else if let current = items[pid] {
                                await MainActor.run {
                                    if !current.locked { current.anchor.setTransformMatrix(pose, relativeTo: nil) }
                                }
                            } else {
                                await MainActor.run {
                                    let a = AnchorEntity()
                                    a.setTransformMatrix(pose, relativeTo: nil)

                                    let quad = ModelEntity(
                                        mesh: .generatePlane(width: 0.8, depth: 0.8),
                                        materials: [baseMat]
                                    )
                                    quad.name = "tableHighlight"
                                    quad.isEnabled = false                               // hidden by default
                                    quad.generateCollisionShapes(recursive: true)
                                    quad.components.set(InputTargetComponent())

                                    a.addChild(quad)
                                    root.addChild(a)
                                    items[pid] = PlaneItem(anchor: a, quad: quad, locked: false)
                                }
                            }
                        case .removed:
                            break
                        }
                    }
                }

                // Gaze focus
                Task {
                    while true {
                        if let dev = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
                            let m = dev.originFromAnchorTransform
                            let camPos = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
                            let camFwd = -SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)

                            var best: (id: UUID, dot: Float)? = nil
                            for (id, item) in items {
                                let t  = item.anchor.transformMatrix(relativeTo: nil)
                                let p  = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
                                let v  = simd_normalize(p - camPos)
                                let d  = simd_dot(camFwd, v)
                                if best == nil || d > best!.dot { best = (id, d) }
                            }
                            await MainActor.run {
                                if let b = best, b.dot >= 0.95 { setActive(b.id) } else { clearActive() }
                            }
                        }
                        try? await Task.sleep(nanoseconds: 33_000_000)
                    }
                }
            }
            // Rotate focused quad
            .gesture(
                RotationGesture()
                    .targetedToAnyEntity()
                    .onChanged { value in
                        guard let id = activeID, var item = items[id], value.entity == item.quad else { return }
                        if startPoseRot == nil || startAngleRad == nil {
                            startPoseRot  = item.anchor.transformMatrix(relativeTo: nil)
                            startAngleRad = Float(value.gestureValue.radians)
                        }
                        let delta = Float(value.gestureValue.radians) - (startAngleRad ?? 0)
                        let rotated = (startPoseRot ?? matrix_identity_float4x4) * yawRotation(delta)
                        item.anchor.setTransformMatrix(rotated, relativeTo: nil)
                        items[id] = item
                    }
                    .onEnded { _ in
                        if let id = activeID, var item = items[id] { item.locked = true; items[id] = item }
                        startPoseRot = nil; startAngleRad = nil
                    }
            )
            // Nudge focused quad
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .targetedToAnyEntity()
                    .onChanged { value in
                        guard let id = activeID, var item = items[id], value.entity == item.quad else { return }

                        let hitLocal = value.convert(value.location3D, from: .local, to: item.anchor)

                        if !isDragging {
                            isDragging = true
                            startPoseMove = item.anchor.transformMatrix(relativeTo: nil)
                            lastHitLocal  = hitLocal
                            return
                        }
                        guard var last = lastHitLocal, let startPose = startPoseMove else { return }

                        var dx = hitLocal.x - last.x
                        var dz = hitLocal.z - last.z
                        dx = max(-stepClamp, min(stepClamp, dx))
                        dz = max(-stepClamp, min(stepClamp, dz))
                        dx = round(dx / quant) * quant
                        dz = round(dz / quant) * quant

                        let moved = startPose * translation(dx: dx, dy: 0, dz: dz)
                        item.anchor.setTransformMatrix(moved, relativeTo: nil)
                        startPoseMove = moved
                        last.x += dx; last.z += dz
                        lastHitLocal = last
                        items[id] = item
                    }
                    .onEnded { _ in
                        if let id = activeID, var item = items[id] { item.locked = true; items[id] = item }
                        isDragging = false
                        startPoseMove = nil
                        lastHitLocal  = nil
                    }
            )
        }

        // MARK: - Focus visibility
        private func setActive(_ id: UUID) {
            if activeID == id { return }
            if let prev = activeID, let p = items[prev] {
                p.quad.model?.materials = [baseMat]
                p.quad.isEnabled = false            // hide previous
            }
            if let p = items[id] {
                p.quad.model?.materials = [focusMat]
                p.quad.isEnabled = true             // show focused
                activeID = id
            }
        }
        private func clearActive() {
            guard let prev = activeID, let p = items[prev] else { return }
            p.quad.model?.materials = [baseMat]
            p.quad.isEnabled = false                // hide when no focus
            activeID = nil
        }

        // MARK: - Helpers
        private func centerXZ(of m: simd_float4x4) -> SIMD2<Float> { .init(m.columns.3.x, m.columns.3.z) }
        private func nearestItem(to p: SIMD2<Float>, within thresh: Float) -> (UUID, PlaneItem)? {
            var best: (UUID, PlaneItem)?
            var bestDist = thresh
            for (id, item) in items {
                let t = item.anchor.transformMatrix(relativeTo: nil)
                let q = centerXZ(of: t)
                let d = simd_length(p - q)
                if d < bestDist { best = (id, item); bestDist = d }
            }
            return best
        }
        private func yawRotation(_ a: Float) -> simd_float4x4 {
            let c = cos(a), s = sin(a)
            return simd_float4x4(
                SIMD4<Float>( c, 0, s, 0),
                SIMD4<Float>( 0, 1, 0, 0),
                SIMD4<Float>(-s, 0, c, 0),
                SIMD4<Float>( 0, 0, 0, 1)
            )
        }
        private func translation(dx: Float, dy: Float, dz: Float) -> simd_float4x4 {
            simd_float4x4(
                SIMD4<Float>(1, 0, 0, 0),
                SIMD4<Float>(0, 1, 0, 0),
                SIMD4<Float>(0, 0, 1, 0),
                SIMD4<Float>(dx, dy, dz, 1)
            )
        }
    }
}
