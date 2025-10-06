import SwiftUI
import RealityKit
import simd

struct ContentView: View {
    // Dark base colors and darker tap-feedback colors
    private let baseColors: [UIColor] = [
        UIColor(red: 0.55, green: 0.12, blue: 0.12, alpha: 1.0), // dark red
        UIColor(red: 0.12, green: 0.50, blue: 0.18, alpha: 1.0), // dark green
        UIColor(red: 0.12, green: 0.22, blue: 0.60, alpha: 1.0)  // dark blue
    ]
    private let tapColors: [UIColor] = [
        UIColor(red: 0.40, green: 0.08, blue: 0.08, alpha: 1.0),
        UIColor(red: 0.08, green: 0.38, blue: 0.14, alpha: 1.0),
        UIColor(red: 0.08, green: 0.16, blue: 0.45, alpha: 1.0)
    ]

    var body: some View {
        RealityView { content in
            // Root
            let root = Entity()
            content.add(root)

            // Camera
            let cam = PerspectiveCamera()
            cam.position = [0, 0.25, 1.2]
            cam.look(at: [0, 0.075, 0], from: cam.position, relativeTo: nil)
            content.add(cam)

            // Three unlit spheres at z = 0
            let r: Float = 0.075
            let y: Float = r
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
                sphere.generateCollisionShapes(recursive: true)     // hit-testing
                sphere.components.set(InputTargetComponent())        // required for targeted gestures
                root.addChild(sphere)
            }
        }
        // Tap a sphere: brief darker flash
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    guard let model = value.entity as? ModelEntity else { return }
                    guard model.name.hasPrefix("sphere_"),
                          let idxStr = model.name.split(separator: "_").last,
                          let i = Int(idxStr), i < 3 else { return }

                    // feedback: darker color for 200 ms, then restore
                    model.model?.materials = [UnlitMaterial(color: tapColors[i])]
                    Task {
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        model.model?.materials = [UnlitMaterial(color: baseColors[i])]
                    }
                    // TODO: handle click (e.g., navigate, show detail) here
                }
        )
        .frame(minWidth: 600, minHeight: 400)
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
}
