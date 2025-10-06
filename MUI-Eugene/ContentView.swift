import SwiftUI
import RealityKit
import simd

struct ContentView: View {
    // Dark, pleasant colors
    private let baseColors: [UIColor] = [
        UIColor(red: 0.55, green: 0.12, blue: 0.12, alpha: 1.0),
        UIColor(red: 0.12, green: 0.50, blue: 0.18, alpha: 1.0),
        UIColor(red: 0.12, green: 0.22, blue: 0.60, alpha: 1.0)
    ]

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

    var body: some View {
        RealityView { content in
            content.add(root)

            // Camera
            let cam = PerspectiveCamera()
            cam.position = [0, 0.30, 1.2]
            cam.look(at: [0, 0.10, 0], from: cam.position, relativeTo: nil)
            content.add(cam)
            camera = cam

            // Three unlit spheres at z = 0
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

                // Record original world transform
                originalTransforms[sphere.name] = sphere.transformMatrix(relativeTo: nil)
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
                }
                .onEnded { value in
                    guard let model = value.entity as? ModelEntity,
                          model.name.hasPrefix("sphere_") else { pinchStartPos = nil; pinchStartCam = nil; return }
                    pinchStartPos = nil
                    pinchStartCam = nil
                    scheduleReturn(for: model)
                }
        )
        .frame(minWidth: 600, minHeight: 400)
    }

    // Return scheduler
    private func scheduleReturn(for model: ModelEntity) {
        guard let target = originalTransforms[model.name] else { return }
        cancelReturn(for: model.name)
        returnTasks[model.name] = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                model.move(to: Transform(matrix: target), relativeTo: nil, duration: 0.5, timingFunction: .easeInOut)
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
