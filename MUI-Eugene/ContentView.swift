import SwiftUI
import RealityKit
import RealityKitContent
import ARKit
import simd
import QuartzCore
import UIKit

// Marker for draggable roots
struct Draggable: Component {}

private func draggableRoot(from e: Entity) -> Entity? {
    var cur: Entity? = e
    var last: Entity?
    while let c = cur {
        if c.components.has(Draggable.self) { last = c }
        cur = c.parent
    }
    return last
}

struct ContentView: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    var body: some View {
        Text("Opening immersive…")
            .task { _ = await openImmersiveSpace(id: "PlacementSpace") }
    }
}

extension ContentView {
    struct HighlightPlaceConfirmView: View {
        // Providers
        private let session = ARKitSession()
        private let planes  = PlaneDetectionProvider(alignments: [.horizontal])
        private let world   = WorldTrackingProvider()

        // Scene + planes
        @State private var root = Entity()
        struct PlaneItem { var anchor: AnchorEntity; var quad: ModelEntity; var locked: Bool }
        @State private var items: [UUID: PlaneItem] = [:]
        @State private var activeID: UUID?
        @State private var confirmed = false

        // Materials
        private let baseMat  = SimpleMaterial(color: .green.withAlphaComponent(0.0), isMetallic: false)
        private let focusMat = SimpleMaterial(color: .blue.withAlphaComponent(0.35),  isMetallic: false)

        // Plane manipulation
        @State private var isManipulatingPlane = false
        @State private var isDraggingPlane = false
        @State private var startPoseRot: simd_float4x4?
        @State private var startAngleRad: Float?
        @State private var startPoseMove: simd_float4x4?
        @State private var lastHitLocal: SIMD3<Float>?
        private let stepClamp: Float = 0.03
        private let quant: Float     = 0.01
        private let mergeDistance: Float = 0.30

        // UI attachments
        @State private var confirmUI: Entity?
        @State private var infoPanel: Entity?
        @State private var machineUI: Entity?   // machine_ui_anchor UI
        @State private var infoText = ""
        @State private var infoTargetName: String?

        // Laboratory
        private let labAssetName = "Laboratory"
        @State private var labRoot: Entity?

        // Hologram preview (before confirm)
        @State private var previewLab: Entity?

        // Drag state for eugenes
        @State private var dragFrame: Entity?
        @State private var grabOffsetLocal: SIMD3<Float>?

        // Snap-back (WORLD poses)
        @State private var originalWorld: [String: simd_float4x4] = [:]

        // Machine targets (collision vs anchor)
        struct MachineTarget { let name: String; let collisionEntity: Entity; let anchorEntity: Entity? }
        @State private var machines: [MachineTarget] = []

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
                if machineUI == nil, let e = attachments.entity(for: "machineUI") {
                    e.isEnabled = false
                    // No billboard. Inherit surface orientation.
                    root.addChild(e)
                    machineUI = e
                }
            } attachments: {
                Attachment(id: "confirmUI") {
                    Button("Confirm placement") { confirmPlacement() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(12)
                        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Attachment(id: "infoPanel") {
                    Text(infoText)
                        .font(.system(.title3, weight: .semibold))
                        .multilineTextAlignment(.leading)
                        .padding(12)
                        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Attachment(id: "machineUI") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Machine Controls").font(.headline)
                        HStack {
                            Button("Start") {}
                            Button("Stop") {}
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(12)
                    .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .task {
                guard PlaneDetectionProvider.isSupported else { return }
                let auth = await session.requestAuthorization(for: [.worldSensing])
                guard auth[.worldSensing] == .allowed else { return }
                try? await session.run([planes, world])

                // Preload hologram preview
                Task {
                    do {
                        let ghost = try await Entity(named: labAssetName, in: realityKitContentBundle)
                        ghost.name = "PreviewLab"
                        stripAutoFacingAndAnchoring(in: ghost)
                        disableInteraction(for: ghost)
                        applyHologram(to: ghost)
                        ghost.isEnabled = false
                        root.addChild(ghost)
                        previewLab = ghost
                    } catch { print("Preview load failed: \(error)") }
                }

                // Plane updates
                Task {
                    for await up in planes.anchorUpdates {
                        if confirmed { continue }
                        let pid  = up.anchor.id
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

                // Gaze focus
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

            // Plane rotate
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
                        Task {
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            isManipulatingPlane = false
                            if let id = activeID { updateConfirmUI(for: id) }
                        }
                    }
            )
            // Plane move
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
                        Task {
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            isManipulatingPlane = false
                            if let id = activeID { updateConfirmUI(for: id) }
                        }
                    }
            )
            // Confirm tap
            .simultaneousGesture(
                SpatialTapGesture().targetedToAnyEntity().onEnded { value in
                    guard !confirmed,
                          let ui = confirmUI,
                          ui.isEnabled,
                          value.entity == ui else { return }
                    confirmPlacement()
                }
            )

            // Drag Eugenes with anchor-on-collide
            .simultaneousGesture(
                DragGesture(minimumDistance: 0).targetedToAnyEntity()
                    .onChanged { value in
                        guard confirmed,
                              let model = draggableRoot(from: value.entity),
                              let dev = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else { return }

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

                            let grabScene   = value.convert(value.location3D, from: .local, to: .scene)
                            let grabInFrame = frame.convert(position: grabScene, from: nil)
                            let localAtGrab = model.position(relativeTo: frame)
                            grabOffsetLocal = localAtGrab - grabInFrame
                            return
                        }

                        guard let frame = dragFrame, let gOffset = grabOffsetLocal else { return }
                        let pScene = value.convert(value.location3D, from: .local, to: .scene)
                        let p = frame.convert(position: pScene, from: nil)
                        let target = p + gOffset

                        let alpha: Float = 0.25
                        let current = model.position(relativeTo: frame)
                        let smoothed = current + (target - current) * alpha
                        model.setPosition(smoothed, relativeTo: frame)

                        if infoTargetName == model.name { placeInfoPanel(above: model) }
                    }
                    .onEnded { value in
                        guard confirmed,
                              let model = draggableRoot(from: value.entity) else {
                            cleanupDrag(); return
                        }
                        cleanupDrag()

                        if !anchorIfColliding(model) {
                            returnToOrigin(model)
                        }
                    }
            )
            // Tap info
            .simultaneousGesture(
                SpatialTapGesture().targetedToAnyEntity()
                    .onEnded { value in
                        guard confirmed,
                              let model = draggableRoot(from: value.entity) else { return }
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

        // MARK: Confirm
        private func confirmPlacement() {
            guard let id = activeID, let item = items[id] else { return }
            confirmed = true
            for (_, v) in items { v.quad.isEnabled = false }
            confirmUI?.isEnabled = false
            if let ghost = previewLab { ghost.removeFromParent(); previewLab = nil }

            Task {
                do {
                    let lab = try await Entity(named: labAssetName, in: realityKitContentBundle)
                    lab.name = "LaboratoryRoot"
                    stripAutoFacingAndAnchoring(in: lab)

                    let planeWorld = item.anchor.transformMatrix(relativeTo: nil)
                    lab.setTransformMatrix(planeWorld, relativeTo: nil)
                    root.addChild(lab)
                    labRoot = lab

                    // Attach machine UI to machine_ui_anchor and keep orientation
                    if let anchor = lab.findEntity(named: "machine_ui_anchor"),
                       let ui = machineUI {
                        ui.components[BillboardComponent.self] = nil
                        ui.setParent(anchor)
                        ui.transform = .identity
                        ui.position.y += 0.02
                        ui.isEnabled = true
                    }

                    recordSpawnWorldPoses(for: lab)
                    markEugeneSubtreesDraggable(under: lab)
                    setupMachineTargets()
                } catch { print("Load \(labAssetName) failed: \(error)") }
            }
        }

        // MARK: Anchoring on collide
        private func setupMachineTargets() {
            guard let lab = labRoot else { return }

            func first(named candidates: [String]) -> Entity? {
                for n in candidates { if let e = lab.findEntity(named: n) { return e } }
                return nil
            }
            func socketOrSelf(_ e: Entity) -> Entity {
                if let s = findFirstDescendant(containingAnyOf: ["socket","dock","slot","mount","attach"], under: e) { return s }
                return e
            }

            var list: [MachineTarget] = []

            if let m1 = first(named: ["Machine_1","machine_1","machine1"]) {
                let a1 = first(named: ["machine_1_anchor","Machine_1_anchor","Machine_1_Anchor"])
                list.append(.init(name: "machine1", collisionEntity: socketOrSelf(m1), anchorEntity: a1))
            }
            if let m2 = first(named: ["Machine_2","machine_2","machine2"]) {
                let a2 = first(named: ["machine_2_anchor","Machine_2_anchor","Machine_2_Anchor"])
                list.append(.init(name: "machine2", collisionEntity: socketOrSelf(m2), anchorEntity: a2))
            }

            machines = list
        }

        private func anchorIfColliding(_ model: Entity) -> Bool {
            guard !machines.isEmpty else { return false }

            let a = model.visualBounds(relativeTo: nil)
            let aMin = a.center - a.extents * 0.5
            let aMax = a.center + a.extents * 0.5

            for mt in machines {
                let b = mt.collisionEntity.visualBounds(relativeTo: nil)
                let pad: SIMD3<Float> = .init(repeating: 0.03)
                let bMin = b.center - b.extents * 0.5 - pad
                let bMax = b.center + b.extents * 0.5 + pad

                if overlaps(aMin, aMax, bMin, bMax) {
                    anchorToSpot(model, using: mt)
                    return true
                }
            }
            return false
        }

        private func anchorToSpot(_ model: Entity, using mt: MachineTarget) {
            let anchor = mt.anchorEntity ?? mt.collisionEntity

            let worldT = anchor.transformMatrix(relativeTo: nil)
            model.move(to: Transform(matrix: worldT),
                       relativeTo: nil,
                       duration: 0.20,
                       timingFunction: .easeInOut)

            Task {
                try? await Task.sleep(nanoseconds: 220_000_000)
                await MainActor.run {
                    model.setParent(anchor)
                    model.transform = .identity
                    model.components[Draggable.self] = nil
                    if infoTargetName == model.name { infoPanel?.isEnabled = false; infoTargetName = nil }
                }
            }
        }

        // MARK: Helpers that were missing

        private func setActive(_ id: UUID) {
            if activeID == id { return }
            if let prev = activeID, let p = items[prev] {
                p.quad.model?.materials = [baseMat]; p.quad.isEnabled = false
            }
            if let p = items[id] {
                p.quad.model?.materials = [focusMat]
                p.quad.isEnabled = true
                activeID = id
                updateConfirmUI(for: id)
                if let ghost = previewLab, !confirmed {
                    ghost.setParent(p.anchor)
                    ghost.transform = .identity
                    ghost.isEnabled = true
                }
            }
        }

        private func clearActive() {
            guard let prev = activeID, let p = items[prev] else { return }
            p.quad.model?.materials = [baseMat]; p.quad.isEnabled = false
            activeID = nil
            confirmUI?.isEnabled = false
            previewLab?.isEnabled = false
            previewLab?.setParent(root)
        }

        private func updateConfirmUI(for id: UUID) {
            guard let item = items[id], let ui = confirmUI else { return }
            ui.setParent(item.anchor)
            ui.position = [0, 0.40, 0]
            ui.isEnabled = (!isManipulatingPlane && !confirmed)
        }

        private func makeInfoText(for model: Entity) -> String {
            let name = model.name.isEmpty ? "Item" : model.name
            let p = model.position(relativeTo: nil)
            var distanceStr = "n/a"
            if let dev = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
                let cam = SIMD3<Float>(dev.originFromAnchorTransform.columns.3.x,
                                       dev.originFromAnchorTransform.columns.3.y,
                                       dev.originFromAnchorTransform.columns.3.z)
                distanceStr = String(format: "%.2f m", simd_length(p - cam))
            }
            let posStr = String(format: "x: %.2f  y: %.2f  z: %.2f", p.x, p.y, p.z)
            return "\(name)\nPosition: \(posStr)\nDistance to viewer: \(distanceStr)"
        }

        private func placeInfoPanel(above model: Entity) {
            guard let panel = infoPanel else { return }
            panel.setParent(model)
            panel.position = [0, 0.18, 0]
        }

        private func returnToOrigin(_ model: Entity) {
            guard let targetWorld = originalWorld[model.name] else { return }
            model.move(to: Transform(matrix: targetWorld),
                       relativeTo: nil,
                       duration: 0.35,
                       timingFunction: .easeInOut)
            if infoTargetName == model.name { placeInfoPanel(above: model) }
        }

        private func cleanupDrag() {
            grabOffsetLocal = nil
            if let f = dragFrame { f.removeFromParent() }
            dragFrame = nil
        }

        // MARK: Utilities

        private func overlaps(_ amin: SIMD3<Float>, _ amax: SIMD3<Float>,
                              _ bmin: SIMD3<Float>, _ bmax: SIMD3<Float>) -> Bool {
            return (amin.x <= bmax.x && amax.x >= bmin.x) &&
                   (amin.y <= bmax.y && amax.y >= bmin.y) &&
                   (amin.z <= bmax.z && amax.z >= bmin.z)
        }

        private func findFirst(in root: Entity, names: [String]) -> Entity? {
            for n in names { if let e = root.findEntity(named: n) { return e } }
            return nil
        }

        private func findFirstDescendant(containingAnyOf tokens: [String], under root: Entity) -> Entity? {
            var stack: [Entity] = [root]
            while let e = stack.popLast() {
                let lname = e.name.lowercased()
                if tokens.contains(where: { lname.contains($0) }) { return e }
                stack.append(contentsOf: e.children)
            }
            return nil
        }

        private func applyHologram(to root: Entity) {
            func tint(_ e: Entity) {
                if let m = e as? ModelEntity {
                    m.model?.materials = [UnlitMaterial(color: UIColor.cyan.withAlphaComponent(0.35))]
                    m.components[GroundingShadowComponent.self] = nil
                }
                e.components[CollisionComponent.self] = nil
                e.components[InputTargetComponent.self] = nil
                for c in e.children { tint(c) }
            }
            tint(root)
        }

        private func disableInteraction(for root: Entity) {
            func walk(_ e: Entity) {
                e.components[CollisionComponent.self] = nil
                e.components[InputTargetComponent.self] = nil
                for c in e.children { walk(c) }
            }
            walk(root)
        }

        private func stripAutoFacingAndAnchoring(in root: Entity) {
            if root.components.has(BillboardComponent.self) { root.components[BillboardComponent.self] = nil }
            if root.components.has(AnchoringComponent.self) { root.components[AnchoringComponent.self] = nil }
            for c in root.children { stripAutoFacingAndAnchoring(in: c) }
        }

        private func recordSpawnWorldPoses(for root: Entity) {
            func dfs(_ e: Entity) {
                originalWorld[e.name] = e.transformMatrix(relativeTo: nil)
                for c in e.children { dfs(c) }
            }
            dfs(root)
        }

        private func markEugeneSubtreesDraggable(under root: Entity) {
            var eugeneRoots: [Entity] = []

            func isEugeneName(_ s: String) -> Bool {
                let l = s.lowercased()
                if l.hasPrefix("eugene") { return true }
                return l.contains("eugene 1") || l.contains("eugene 2") || l.contains("eugene 3")
                    || l.contains("eugene 4") || l.contains("eugene 5")
            }
            func collect(_ e: Entity) {
                if isEugeneName(e.name) {
                    var top: Entity = e
                    var p = e.parent
                    while let pp = p, isEugeneName(pp.name) { top = pp; p = pp.parent }
                    if !eugeneRoots.contains(where: { $0 === top }) { eugeneRoots.append(top) }
                }
                for c in e.children { collect(c) }
            }
            collect(root)

            if eugeneRoots.isEmpty {
                for c in root.children where c is ModelEntity { eugeneRoots.append(c) }
            }

            var used = Set(originalWorld.keys)
            func unique(_ base: String) -> String {
                let b = base.isEmpty ? "eugene" : base
                if !used.contains(b) { used.insert(b); return b }
                while true {
                    let t = b + "_" + UUID().uuidString.prefix(4)
                    if !used.contains(t) { used.insert(t); return t }
                }
            }

            for r in eugeneRoots {
                r.components.set(Draggable())
                if r.name.isEmpty || originalWorld[r.name] != nil { r.name = unique(r.name) }

                r.generateCollisionShapes(recursive: true)
                r.components.set(InputTargetComponent())
                func tagDesc(_ e: Entity) {
                    if let m = e as? ModelEntity {
                        if m.components[CollisionComponent.self] == nil { m.generateCollisionShapes(recursive: false) }
                        m.components.set(InputTargetComponent())
                    }
                    for c in e.children { tagDesc(c) }
                }
                tagDesc(r)

                if originalWorld[r.name] == nil {
                    originalWorld[r.name] = r.transformMatrix(relativeTo: nil)
                }
            }
        }

        // Math
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
