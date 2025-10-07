import SwiftUI
import RealityKit
import ARKit
import simd
import QuartzCore
import UIKit

struct ContentView: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    var body: some View {
        Text("Opening immersive…").task { _ = await openImmersiveSpace(id: "PlacementSpace") }
    }
}

extension ContentView {
    struct HighlightPlaceConfirmView: View {
        // Providers
        private let session = ARKitSession()
        private let planes  = PlaneDetectionProvider(alignments: [.horizontal])
        private let world   = WorldTrackingProvider()

        // Scene
        @State private var root = Entity()
        struct PlaneItem { var anchor: AnchorEntity; var quad: ModelEntity; var locked: Bool }
        @State private var items: [UUID: PlaneItem] = [:]
        @State private var activeID: UUID?

        // Surface visuals
        private let baseMat  = SimpleMaterial(color: .green.withAlphaComponent(0.0), isMetallic: false)
        private let focusMat = SimpleMaterial(color: .blue.withAlphaComponent(0.35),  isMetallic: false)

        // Flow
        @State private var confirmed = false
        private let mergeDistance: Float = 0.30

        // Plane manipulation
        @State private var startPoseRot: simd_float4x4?
        @State private var startAngleRad: Float?
        @State private var isDraggingPlane = false
        @State private var startPoseMove: simd_float4x4?
        @State private var lastHitLocal: SIMD3<Float>?
        private let stepClamp: Float = 0.03
        private let quant: Float     = 0.01
        @State private var isManipulatingPlane = false

        // Confirm UI
        @State private var confirmUI: Entity?

        // Spheres after confirm
        private let baseColors: [UIColor] = [
            UIColor(red: 0.55, green: 0.12, blue: 0.12, alpha: 1.0),
            UIColor(red: 0.12, green: 0.50, blue: 0.18, alpha: 1.0),
            UIColor(red: 0.12, green: 0.22, blue: 0.60, alpha: 1.0)
        ]
        private let colorNames = ["Dark Red", "Dark Green", "Dark Blue"]

        @State private var spheresRig: Entity?
        @State private var originalLocal: [String: simd_float4x4] = [:]
        @State private var returnTasks: [String: Task<Void, Never>] = [:]

        // Drag (sphere) on camera-aligned frame. Absolute mapping, XYZ free.
        @State private var dragFrame: Entity?
        @State private var grabOffsetLocal: SIMD3<Float>?

        // Info panel
        @State private var infoPanel: Entity?
        @State private var infoText: String = ""
        @State private var infoTargetName: String?

        var body: some View {
            RealityView { content, attachments in
                content.add(root)

                if confirmUI == nil, let e = attachments.entity(for: "confirmUI") {
                    e.isEnabled = false
                    e.components.set(BillboardComponent())
                    root.addChild(e)
                    confirmUI = e
                }
                if infoPanel == nil, let e = attachments.entity(for: "infoPanel") {
                    e.isEnabled = false
                    e.components.set(BillboardComponent())
                    root.addChild(e)
                    infoPanel = e
                }
            } attachments: {
                Attachment(id: "confirmUI") {
                    Button("Confirm placement") { confirmPlacement() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(8)
                }
                Attachment(id: "infoPanel") {
                    Text(infoText)
                        .font(.system(.title3, weight: .semibold))
                        .multilineTextAlignment(.leading)
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(2)
                }
            }
            .task {
                guard PlaneDetectionProvider.isSupported else { return }
                let auth = await session.requestAuthorization(for: [.worldSensing])
                guard auth[.worldSensing] == .allowed else { return }
                try? await session.run([planes, world])

                Task {
                    for await up in planes.anchorUpdates {
                        if confirmed { continue }
                        let pid = up.anchor.id
                        let pose = up.anchor.originFromAnchorTransform
                        switch up.event {
                        case .added, .updated:
                            guard up.anchor.surfaceClassification == .table else { continue }
                            if let item = items[pid], item.locked { continue }

                            let center = centerXZ(of: pose)
                            if let (existingID, existing) = nearestItem(to: center, within: mergeDistance) {
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
                                    let a = AnchorEntity(); a.setTransformMatrix(pose, relativeTo: nil)
                                    let quad = ModelEntity(mesh: .generatePlane(width: 0.8, depth: 0.8),
                                                           materials: [baseMat])
                                    quad.name = "tableHighlight"
                                    quad.isEnabled = false
                                    quad.generateCollisionShapes(recursive: true)
                                    quad.components.set(InputTargetComponent())
                                    a.addChild(quad); root.addChild(a)
                                    items[pid] = PlaneItem(anchor: a, quad: quad, locked: false)
                                }
                            }
                        case .removed: break
                        }
                    }
                }

                // Gaze focus to select one surface
                Task {
                    while !confirmed {
                        if let dev = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
                            let m = dev.originFromAnchorTransform
                            let camPos = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
                            let camFwd = -SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)
                            var best: (id: UUID, dot: Float)? = nil
                            for (id, item) in items {
                                let t = item.anchor.transformMatrix(relativeTo: nil)
                                let p = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
                                let v = simd_normalize(p - camPos)
                                let d = simd_dot(camFwd, v)
                                if best == nil || d > best!.dot { best = (id, d) }
                            }
                            await MainActor.run { if let b = best, b.dot >= 0.95 { setActive(b.id) } else { clearActive() } }
                        }
                        try? await Task.sleep(nanoseconds: 33_000_000)
                    }
                }
            }

            // Plane gestures
            .gesture(
                RotationGesture().targetedToAnyEntity()
                    .onChanged { value in
                        guard !confirmed,
                              let id = activeID,
                              let item = items[id],
                              value.entity == item.quad else { return }
                        if !isManipulatingPlane { isManipulatingPlane = true; confirmUI?.isEnabled = false }
                        if startPoseRot == nil || startAngleRad == nil {
                            startPoseRot  = item.anchor.transformMatrix(relativeTo: nil)
                            startAngleRad = Float(value.gestureValue.radians)
                        }
                        let delta = Float(value.gestureValue.radians) - (startAngleRad ?? 0)
                        let rotated = (startPoseRot ?? matrix_identity_float4x4) * yaw(delta)
                        item.anchor.setTransformMatrix(rotated, relativeTo: nil)
                    }
                    .onEnded { _ in
                        guard !confirmed else { return }
                        if let id = activeID, var item = items[id] { item.locked = true; items[id] = item }
                        startPoseRot = nil; startAngleRad = nil
                        Task { try? await Task.sleep(nanoseconds: 300_000_000)
                            isManipulatingPlane = false
                            if let id = activeID { updateConfirmUI(for: id) }
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0).targetedToAnyEntity()
                    .onChanged { value in
                        guard !confirmed,
                              let id = activeID,
                              let item = items[id],
                              value.entity == item.quad else { return }
                        if !isDraggingPlane {
                            isDraggingPlane = true
                            isManipulatingPlane = true
                            confirmUI?.isEnabled = false
                            startPoseMove = item.anchor.transformMatrix(relativeTo: nil)
                            let worldP = value.convert(value.location3D, from: .local, to: .scene)
                            lastHitLocal  = item.anchor.convert(position: worldP, from: nil)
                            return
                        }
                        guard var last = lastHitLocal, let startPose = startPoseMove else { return }
                        let worldP = value.convert(value.location3D, from: .local, to: .scene)
                        let hitLocal = item.anchor.convert(position: worldP, from: nil)
                        var dx = hitLocal.x - last.x, dz = hitLocal.z - last.z
                        dx = max(-stepClamp, min(stepClamp, dx))
                        dz = max(-stepClamp, min(stepClamp, dz))
                        dx = round(dx / quant) * quant; dz = round(dz / quant) * quant
                        let moved = startPose * translate(dx: dx, dy: 0, dz: dz)
                        item.anchor.setTransformMatrix(moved, relativeTo: nil)
                        startPoseMove = moved; last.x += dx; last.z += dz; lastHitLocal = last
                    }
                    .onEnded { _ in
                        guard !confirmed else { return }
                        if let id = activeID, var item = items[id] { item.locked = true; items[id] = item }
                        isDraggingPlane = false; startPoseMove = nil; lastHitLocal = nil
                        Task { try? await Task.sleep(nanoseconds: 300_000_000)
                            isManipulatingPlane = false
                            if let id = activeID { updateConfirmUI(for: id) }
                        }
                    }
            )
            // Tap confirm
            .simultaneousGesture(
                SpatialTapGesture().targetedToAnyEntity().onEnded { value in
                    guard !confirmed,
                          let ui = confirmUI,
                          ui.isEnabled,
                          value.entity == ui else { return }
                    confirmPlacement()
                }
            )

            // Sphere gestures — ONE drag handles X/Y/Z
            .simultaneousGesture(
                DragGesture(minimumDistance: 0).targetedToAnyEntity()
                    .onChanged { value in
                        guard confirmed,
                              let model = value.entity as? ModelEntity,
                              model.name.hasPrefix("sphere_"),
                              let dev = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else { return }

                        // Create camera-aligned frame at grab
                        if dragFrame == nil || grabOffsetLocal == nil {
                            let m = dev.originFromAnchorTransform
                            let right   = SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z)
                            let up      = SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z)
                            let forward = -SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)

                            let pos = model.position(relativeTo: nil)
                            var frameMat = matrix_identity_float4x4
                            frameMat.columns.0 = SIMD4<Float>(right,   0)
                            frameMat.columns.1 = SIMD4<Float>(up,      0)
                            frameMat.columns.2 = SIMD4<Float>(forward, 0)
                            frameMat.columns.3 = SIMD4<Float>(pos.x, pos.y, pos.z, 1)

                            let frame = Entity()
                            frame.setTransformMatrix(frameMat, relativeTo: nil)
                            root.addChild(frame)
                            dragFrame = frame

                            let grabScene  = value.convert(value.location3D, from: .local, to: .scene)
                            let grabInFrame = frame.convert(position: grabScene, from: nil)
                            let localAtGrab = model.position(relativeTo: frame)
                            grabOffsetLocal = localAtGrab - grabInFrame
                            return
                        }

                        guard let frame = dragFrame,
                              let gOffset = grabOffsetLocal else { return }

                        // Map pointer scene→frame each update
                        let pScene = value.convert(value.location3D, from: .local, to: .scene)
                        let p = frame.convert(position: pScene, from: nil)

                        // Absolute target. No z lock. This gives forward/back with hand.
                        let target = p + gOffset

                        // Mild smoothing
                        let alpha: Float = 0.25
                        let current = model.position(relativeTo: frame)
                        let smoothed = current + (target - current) * alpha
                        model.setPosition(smoothed, relativeTo: frame)

                        if infoTargetName == model.name { placeInfoPanel(above: model) }
                    }
                    .onEnded { value in
                        guard confirmed,
                              let model = value.entity as? ModelEntity,
                              model.name.hasPrefix("sphere_") else { cleanupDrag(); return }
                        cleanupDrag()
                        scheduleReturn(for: model)
                    }
            )
            // Tap to toggle info
            .simultaneousGesture(
                SpatialTapGesture().targetedToAnyEntity()
                    .onEnded { value in
                        guard confirmed,
                              let model = value.entity as? ModelEntity,
                              model.name.hasPrefix("sphere_") else { return }
                        if infoTargetName == model.name {
                            infoTargetName = nil
                            infoPanel?.isEnabled = false
                        } else {
                            infoTargetName = model.name
                            infoText = makeInfoText(for: model)
                            placeInfoPanel(above: model)
                            infoPanel?.isEnabled = true
                        }
                    }
            )
        }

        // Confirm: spawn spheres on selected surface
        private func confirmPlacement() {
            guard let id = activeID, let item = items[id] else { return }
            confirmed = true
            for (_, v) in items { v.quad.isEnabled = false }
            confirmUI?.isEnabled = false

            let rig = Entity()
            rig.position = .zero
            item.anchor.addChild(rig)
            spheresRig = rig

            let r: Float = 0.075, y: Float = r
            let localPositions: [SIMD3<Float>] = [
                [-0.20, y,  0.0],
                [ 0.00, y,  0.0],
                [ 0.20, y,  0.0]
            ]
            let mesh = MeshResource.generateSphere(radius: r)
            for i in 0..<3 {
                let mat = UnlitMaterial(color: baseColors[i])
                let sphere = ModelEntity(mesh: mesh, materials: [mat])
                sphere.name = "sphere_\(i)"
                sphere.position = localPositions[i]
                sphere.generateCollisionShapes(recursive: true)
                sphere.components.set(InputTargetComponent())
                rig.addChild(sphere)
                originalLocal[sphere.name] = sphere.transformMatrix(relativeTo: rig)
            }
        }

        // Focus + confirm UI
        private func setActive(_ id: UUID) {
            if activeID == id { return }
            if let prev = activeID, let p = items[prev] { p.quad.model?.materials = [baseMat]; p.quad.isEnabled = false }
            if let p = items[id] {
                p.quad.model?.materials = [focusMat]
                p.quad.isEnabled = true
                activeID = id
                updateConfirmUI(for: id)
            }
        }
        private func clearActive() {
            guard let prev = activeID, let p = items[prev] else { return }
            p.quad.model?.materials = [baseMat]; p.quad.isEnabled = false
            activeID = nil
            confirmUI?.isEnabled = false
        }
        private func updateConfirmUI(for id: UUID) {
            guard let item = items[id], let ui = confirmUI else { return }
            ui.setParent(item.anchor)
            ui.position = [0, 0.40, 0]
            ui.isEnabled = (!isManipulatingPlane && !confirmed)
        }

        // Info
        private func makeInfoText(for model: ModelEntity) -> String {
            let idx = Int(model.name.split(separator: "_").last ?? "0") ?? 0
            let colorName = colorNames[min(max(idx, 0), colorNames.count - 1)]
            let p = model.position(relativeTo: nil)
            let posStr = String(format: "x: %.2f  y: %.2f  z: %.2f", p.x, p.y, p.z)
            var distanceStr = "n/a"
            if let dev = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
                let cam = SIMD3<Float>(dev.originFromAnchorTransform.columns.3.x,
                                       dev.originFromAnchorTransform.columns.3.y,
                                       dev.originFromAnchorTransform.columns.3.z)
                distanceStr = String(format: "%.2f m", simd_length(p - cam))
            }
            return """
            Sphere \(idx + 1)
            Color: \(colorName)
            Radius: 7.5 cm
            Position: \(posStr)
            Distance to viewer: \(distanceStr)
            """
        }
        private func placeInfoPanel(above model: ModelEntity) {
            guard let panel = infoPanel else { return }
            panel.setParent(model)
            panel.position = [0, 0.18, 0]
        }

        // Auto-return
        private func scheduleReturn(for model: ModelEntity) {
            guard let rig = spheresRig,
                  let targetLocal = originalLocal[model.name] else { return }
            cancelReturn(for: model.name)
            returnTasks[model.name] = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    model.move(to: Transform(matrix: targetLocal),
                               relativeTo: rig,
                               duration: 0.5,
                               timingFunction: .easeInOut)
                    if infoTargetName == model.name { placeInfoPanel(above: model) }
                }
            }
        }
        private func cancelReturn(for name: String) {
            if let t = returnTasks[name] { t.cancel(); returnTasks.removeValue(forKey: name) }
        }
        private func cleanupDrag() {
            grabOffsetLocal = nil
            if let f = dragFrame { f.removeFromParent() }
            dragFrame = nil
        }

        // Helpers
        private func centerXZ(of m: simd_float4x4) -> SIMD2<Float> { .init(m.columns.3.x, m.columns.3.z) }
        private func nearestItem(to p: SIMD2<Float>, within thresh: Float) -> (UUID, PlaneItem)? {
            var best: (UUID, PlaneItem)?; var bestDist = thresh
            for (id, item) in items {
                let t = item.anchor.transformMatrix(relativeTo: nil)
                let q = centerXZ(of: t); let d = simd_length(p - q)
                if d < bestDist { best = (id, item); bestDist = d }
            }
            return best
        }
        private func yaw(_ a: Float) -> simd_float4x4 {
            let c = cos(a), s = sin(a)
            return simd_float4x4(
                SIMD4<Float>( c, 0, s, 0),
                SIMD4<Float>( 0, 1, 0, 0),
                SIMD4<Float>(-s, 0, c, 0),
                SIMD4<Float>( 0, 0, 0, 1)
            )
        }
        private func translate(dx: Float, dy: Float, dz: Float) -> simd_float4x4 {
            simd_float4x4(
                SIMD4<Float>(1, 0, 0, 0),
                SIMD4<Float>(0, 1, 0, 0),
                SIMD4<Float>(0, 0, 1, 0),
                SIMD4<Float>(dx, dy, dz, 1)
            )
        }
    }
}
