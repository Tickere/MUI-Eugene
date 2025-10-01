//
//  ContentView.swift
//  MUI-Eugene
//
//  Created by Pablo Blumer on 01.10.2025.
//

import SwiftUI
import RealityKit
import RealityKitContent

// MARK: - Navigation

enum Route: Hashable {
    case punnett
    case place
}

// MARK: - Root

struct ContentView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            StartView {
                path.append(Route.punnett)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .punnett:
                    PunnettSquareView {
                        path.append(Route.place)
                    }
                case .place:
                    PlaceView()
                }
            }
            .navigationTitle("Start")
        }
    }
}

// MARK: - Step 1: Start

struct StartView: View {
    var onStart: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Model3D(named: "Scene", bundle: realityKitContentBundle)
                .frame(maxHeight: 300)

            Text("Hello")
                .font(.largeTitle).bold()

            Button("Start") { onStart() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Step 2: Punnett

struct PunnettSquareView: View {
    // Inputs
    @State private var parentA: String = "Aa"
    @State private var parentB: String = "Aa"

    // Derived
    private var allelesA: [String] { splitAlleles(parentA) }
    private var allelesB: [String] { splitAlleles(parentB) }
    private var grid: [[String]] { makeGrid(allelesA, allelesB) }
    private var summary: [(String, Int, Double)] { genotypeSummary(grid) }
    private var phenotypeSummaryText: String { phenotypeSummary(summary) }

    var onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Inputs
                VStack(alignment: .leading, spacing: 8) {
                    Text("Parents").font(.headline)
                    HStack {
                        TextField("Parent A (e.g. Aa)", text: $parentA)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.characters)
                            .keyboardType(.asciiCapable)
                            .autocorrectionDisabled()

                        TextField("Parent B (e.g. Aa)", text: $parentB)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.characters)
                            .keyboardType(.asciiCapable)
                            .autocorrectionDisabled()
                    }
                    Text("Enter two alleles per parent, e.g. AA, Aa, or aa.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // Grid
                VStack(alignment: .leading, spacing: 8) {
                    Text("Punnett Square").font(.headline)

                    if allelesA.count == 2 && allelesB.count == 2 {
                        PunnettGridView(allelesA: allelesA, allelesB: allelesB, grid: grid)
                    } else {
                        Text("Invalid input. Use exactly two letters per parent.")
                            .foregroundStyle(.red)
                    }
                }

                // Results
                if allelesA.count == 2 && allelesB.count == 2 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Genotype Ratios").font(.headline)
                        ForEach(summary, id: \.0) { (g, c, p) in
                            HStack {
                                Text(g).monospaced()
                                Spacer()
                                Text("\(c)/4  (\(formatPct(p)))")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text("Phenotype (uppercase dominant):")
                            .font(.headline)
                            .padding(.top, 8)
                        Text(phenotypeSummaryText)
                            .monospaced()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top)
        }
        .navigationTitle("Punnett")
        // Bottom-centered Continue button, same look as Start
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Continue") { onContinue() }
                    .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding(.vertical, 12)   // no background
        }
    }
}

// MARK: - Step 3: Place

struct PlaceView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Place")
                .font(.largeTitle).bold()
            Text("Third window.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Place")
    }
}

// MARK: - Grid View

struct PunnettGridView: View {
    let allelesA: [String]   // top headers
    let allelesB: [String]   // side headers
    let grid: [[String]]     // 2x2 cells

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 3)

        LazyVGrid(columns: columns, spacing: 0) {
            GridCell(text: "", isHeader: true)

            GridCell(text: allelesA[0], isHeader: true)
            GridCell(text: allelesA[1], isHeader: true)

            GridCell(text: allelesB[0], isHeader: true)
            GridCell(text: grid[0][0])
            GridCell(text: grid[0][1])

            GridCell(text: allelesB[1], isHeader: true)
            GridCell(text: grid[1][0])
            GridCell(text: grid[1][1])
        }
        .frame(maxWidth: 420)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.secondary.opacity(0.3), lineWidth: 1)
        )
    }
}

struct GridCell: View {
    let text: String
    var isHeader: Bool = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isHeader ? Color.secondary.opacity(0.08) : Color.clear)
                .frame(height: 64)
                .overlay(Rectangle().stroke(.secondary.opacity(0.2), lineWidth: 0.5))

            Text(text)
                .font(isHeader ? .headline : .body)
                .monospaced()
        }
    }
}

// MARK: - Logic

private func splitAlleles(_ s: String) -> [String] {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count == 2 else { return [] }
    return trimmed.map { String($0) }
}

private func makeGrid(_ a: [String], _ b: [String]) -> [[String]] {
    guard a.count == 2, b.count == 2 else { return [] }
    func combine(_ x: String, _ y: String) -> String {
        let pair = [x, y]
        let sorted = pair.sorted { lhs, rhs in
            if lhs == rhs { return false }
            let lUpper = lhs.uppercased()
            let rUpper = rhs.uppercased()
            if lUpper == rUpper { return lhs < rhs }
            return lUpper < rUpper
        }
        return sorted.joined()
    }
    return [
        [combine(a[0], b[0]), combine(a[1], b[0])],
        [combine(a[0], b[1]), combine(a[1], b[1])]
    ]
}

private func genotypeSummary(_ grid: [[String]]) -> [(String, Int, Double)] {
    let flat = grid.flatMap { $0 }
    var counts: [String: Int] = [:]
    for g in flat { counts[g, default: 0] += 1 }
    let total = Double(flat.count)
    return counts
        .sorted { $0.key < $1.key }
        .map { (k, v) in (k, v, Double(v) / total) }
}

private func phenotypeSummary(_ items: [(String, Int, Double)]) -> String {
    var dom = 0
    var rec = 0
    for (g, c, _) in items {
        if let first = g.first {
            let base = String(first).uppercased()
            let hasUpper = g.contains { String($0) == base }
            let hasLower = g.contains { String($0) == base.lowercased() }
            if hasUpper { dom += c } else if hasLower { rec += c }
        }
    }
    return "Dominant: \(dom)/4, Recessive: \(rec)/4"
}

private func formatPct(_ p: Double) -> String {
    String(format: "%.0f%%", p * 100.0)
}

#Preview(windowStyle: .automatic) {
    ContentView()
}
