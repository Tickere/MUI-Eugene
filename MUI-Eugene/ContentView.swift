import SwiftUI
import RealityKit
import simd

struct ContentView: View {
    // Dark, pleasant colors
    private let baseColors: [UIColor] = [
        UIColor(red: 0.55, green: 0.12, blue: 0.12, alpha: 1.0), // dark red
        UIColor(red: 0.12, green: 0.50, blue: 0.18, alpha: 1.0), // dark green
        UIColor(red: 0.12, green: 0.22, blue: 0.60, alpha: 1.0)  // dark blue
    ]
    private let colorNames = ["Dark Red", "Dark Green", "Dark Blue"]

    @State private var root = Entity()
    @State private var camera: PerspectiveCamera?

    // Drag state
    @State private var dragStartPose: simd_float4x4?
    @State private var dragLastWorld: SIMD3<Float>?

    // Pinch state
    @State private var pinchStartPos: SIMD3<Float>?
    @State private var pinchStartCam: SIMD3<Float>?

    // Original transforms and pending returns
    @State private var originalTransforms: [String: simd_float4x4] = [:]
    @State private var returnTasks: [String: Task<Void, Never>] = [:]

    // Info panel attachment
    @State private var infoPanel: Entity?
    @State private var infoText: String = ""
    @State private var infoTargetName: String?

    var body: some View {
        RealityView { content, attachments in
            content.add(root)

            // Camera
            let cam = PerspectiveCamera()
            cam.position = [0, 0.30, 1.2]
            cam.look(at: [0, 0.10, 0], from: cam.position, relativeTo: nil)
            content.add(cam)
            camera = cam

            // Spheres
            let r: Float = 0.075, y: Float = r
            let positions: [SIMD3<Float>] = [
                [-0.20, y, 0.0],
                [ 0.00, y, 0.0],
                [ 0.20, y, 0.0]
            ]
            let mesh = MeshResource.generateSphere(radius: r)
            for (i, p) in positions.enumerated() {
                let mat = UnlitMaterial(color: baseColors[i])
                let sphere = ModelEntity(mesh: mesh, materials: [mat])
                sphere.name = "sphere_\(i)"
                sphere.position = p
                sphere.generateCollisionShapes(recursive: true)
                sphere.components.set(InputTargetComponent())
                root.addChild(sphere)
                originalTransforms[sphere.name] = sphere.transformMatrix(relativeTo: nil)
            }

            // Create info panel attachment once
            if infoPanel == nil, let e = attachments.entity(for: "infoPanel") {
                e.isEnabled = false
                e.components.set(BillboardComponent()) // face viewer
                root.addChild(e)
                infoPanel = e
            }
        } attachments: {
            Attachment(id: "infoPanel") {
                Text(infoText)
                    .font(.system(.title3, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(2)
            }
        }
        // Drag: move in world XYZ
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).targetedToAnyEntity()
                .onChanged { value in
                    guard let model = value.entity as? ModelEntity,
                          model.name.hasPrefix("sphere_") else { return }

                    cancelReturn(for: model.name)

                    let hitWorld = value.convert(value.location3D, from: .local, to: .scene)

                    if dragStartPose == nil {
                        dragStartPose = model.transformMatrix(relativeTo: nil)
                        dragLastWorld = hitWorld
                        return
                    }
                    guard let last = dragLastWorld, let startPose = dragStartPose else { return }

                    var dx = hitWorld.x - last.x
                    var dy = hitWorld.y - last.y
                    var dz = hitWorld.z - last.z

                    let step: Float = 0.03
                    dx = max(-step, min(step, dx))
                    dy = max(-step, min(step, dy))
                    dz = max(-step, min(step, dz))

                    let moved = startPose * translation(dx: dx, dy: dy, dz: dz)
                    model.setTransformMatrix(moved, relativeTo: nil)

                    dragStartPose = moved
                    dragLastWorld = SIMD3<Float>(last.x + dx, last.y + dy, last.z + dz)

                    // Keep panel above the dragged sphere
                    if infoTargetName == model.name { placeInfoPanel(above: model) }
                }
                .onEnded { value in
                    guard let model = value.entity as? ModelEntity,
                          model.name.hasPrefix("sphere_") else { dragStartPose = nil; dragLastWorld = nil; return }
                    dragStartPose = nil
                    dragLastWorld = nil
                    scheduleReturn(for: model)
                }
        )
        // Pinch: move along camera→sphere ray; keep height
        .simultaneousGesture(
            MagnificationGesture().targetedToAnyEntity()
                .onChanged { value in
                    guard let model = value.entity as? ModelEntity,
                          model.name.hasPrefix("sphere_"),
                          let cam = camera else { return }

                    cancelReturn(for: model.name)

                    let camPos = cam.position(relativeTo: nil)
                    let spherePos = model.position(relativeTo: nil)

                    if pinchStartPos == nil || pinchStartCam == nil {
                        pinchStartPos = spherePos
                        pinchStartCam = camPos
                    }
                    guard let startPos = pinchStartPos, let startCam = pinchStartCam else { return }

                    let dir = simd_normalize(startPos - startCam)
                    let startDist = simd_length(startPos - startCam)

                    let scale = Float(value.gestureValue)
                    var newDist = startDist * scale
                    newDist = max(0.15, min(5.0, newDist))

                    var newPos = startCam + dir * newDist
                    newPos.y = startPos.y
                    model.position = newPos

                    if infoTargetName == model.name { placeInfoPanel(above: model) }
                }
                .onEnded { value in
                    guard let model = value.entity as? ModelEntity,
                          model.name.hasPrefix("sphere_") else { pinchStartPos = nil; pinchStartCam = nil; return }
                    pinchStartPos = nil
                    pinchStartCam = nil
                    scheduleReturn(for: model)
                }
        )
        // Tap: toggle info panel for the tapped sphere
        .simultaneousGesture(
            SpatialTapGesture().targetedToAnyEntity()
                .onEnded { value in
                    guard let model = value.entity as? ModelEntity,
                          model.name.hasPrefix("sphere_") else { return }
                    if infoTargetName == model.name {
                        // toggle off
                        infoTargetName = nil
                        infoPanel?.isEnabled = false
                        return
                    }
                    // update content and show
                    infoTargetName = model.name
                    infoText = makeInfoText(for: model)
                    placeInfoPanel(above: model)
                    infoPanel?.isEnabled = true
                }
        )
        .frame(minWidth: 600, minHeight: 400)
    }

    // MARK: - Info content
    private func makeInfoText(for model: ModelEntity) -> String {
        let idx = Int(model.name.split(separator: "_").last ?? "0") ?? 0
        let colorName = colorNames[min(max(idx, 0), colorNames.count - 1)]
        let p = model.position(relativeTo: nil)
        let radiusCm = 7.5 // matches r: 0.075 m
        var distanceStr = "n/a"
        if let cam = camera {
            let d = simd_length(p - cam.position(relativeTo: nil))
            distanceStr = String(format: "%.2f m", d)
        }
        let posStr = String(format: "x: %.2f  y: %.2f  z: %.2f", p.x, p.y, p.z)
        return """
        Sphere \(idx + 1)
        Color: \(colorName)
        Radius: \(radiusCm) cm
        Position: \(posStr)
        Distance to camera: \(distanceStr)
        """
    }

    private func placeInfoPanel(above model: ModelEntity) {
        guard let panel = infoPanel else { return }
        panel.setParent(model)
        panel.position = [0, 0.18, 0] // 18 cm above the sphere
    }

    // MARK: - Return scheduler
    private func scheduleReturn(for model: ModelEntity) {
        guard let target = originalTransforms[model.name] else { return }
        cancelReturn(for: model.name)
        returnTasks[model.name] = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                model.move(to: Transform(matrix: target), relativeTo: nil, duration: 0.5, timingFunction: .easeInOut)
                if infoTargetName == model.name { placeInfoPanel(above: model) }
            }
        }
    }

    private func cancelReturn(for name: String) {
        if let t = returnTasks[name] {
            t.cancel()
            returnTasks.removeValue(forKey: name)
        }
    }
}

// MARK: - Math
private func translation(dx: Float, dy: Float, dz: Float) -> simd_float4x4 {
    simd_float4x4(
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(dx, dy, dz, 1)
    )
}

#Preview(windowStyle: .automatic) {
    ContentView()
}
