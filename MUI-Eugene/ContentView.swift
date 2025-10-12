//
//  ContentView.swift
//  MUI-Eugene
//
//  Created by Pablo Blumer on 01.10.2025.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
    var body: some View {
        PunnettSquareTabs()
    }
}

// MARK: - Tabs

struct PunnettSquareTabs: View {
    var body: some View {
        TabView {
            PunnettSquareView(defaultGenotype: "", traitName: "Eyes")
                .tabItem { Label("Eyes", systemImage: "eye") }

            PunnettSquareView(defaultGenotype: "", traitName: "Horns")
                .tabItem { Label("Horns", systemImage: "triangle") }

            PunnettSquareView(defaultGenotype: "", traitName: "Colour")
                .tabItem { Label("Colour", systemImage: "paintpalette") }
        }
    }
}

// MARK: - Punnett Square (live-updating)

struct PunnettSquareView: View {
    @State private var parentA: String
    @State private var parentB: String
    private let traitName: String

    init(defaultGenotype: String, traitName: String) {
        _parentA = State(initialValue: defaultGenotype)
        _parentB = State(initialValue: defaultGenotype)
        self.traitName = traitName
    }

    private var headersA: [String] { twoChars(parentA) }
    private var headersB: [String] { twoChars(parentB) }
    private var grid: [[String]] { makeGridPartial(headersA, headersB) }

    private var percentages: (base: String, dom: Double, rec: Double)? {
        traitOutcomeParts(genotypeSummary(grid))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Inputs
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(traitName) — Parents").font(.headline)
                    HStack {
                        TextField("Parent A (e.g. Aa)", text: $parentA)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        TextField("Parent B (e.g. Aa)", text: $parentB)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                    Text("Enter two alleles per parent, e.g. AA, Aa, or aa.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // Grid (no section title)
                PunnettGridView(allelesA: headersA, allelesB: headersB, grid: grid)

                // Outcome (always visible)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Outcome").font(.title.bold())
                    HStack(spacing: 20) {
                        OutcomeCard(
                            title: "\(percentages?.base ?? "A"):",
                            percentText: percentages != nil ? formatPct1(percentages!.dom) : "—"
                        )
                        OutcomeCard(
                            title: "\(percentages?.base.lowercased() ?? "a"):",
                            percentText: percentages != nil ? formatPct1(percentages!.rec) : "—"
                        )
                    }
                }
                .padding(.top, 8)
            }
            .padding()
        }
    }
}

// MARK: - Outcome Card (bold “Outcome” label, medium grey values)

struct OutcomeCard: View {
    let title: String
    let percentText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2.weight(.medium))
            Text(percentText)
                .font(.title2.weight(.medium))
                .foregroundStyle(.tertiary) // grey tone
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
        )
    }
}

// MARK: - Grid View (rounded box, soft strokes)

struct PunnettGridView: View {
    let allelesA: [String]
    let allelesB: [String]
    let grid: [[String]]

    private let boxCorner: CGFloat = 16
    private let boxStroke: CGFloat = 2
    private let boxHeight: CGFloat = 160
    private let leftGutter: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top headers
            HStack(spacing: 0) {
                Spacer().frame(width: leftGutter)
                HStack(spacing: 0) {
                    Text(display(allelesA[0]))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .monospaced()
                    Text(display(allelesA[1]))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .monospaced()
                }
                .frame(maxWidth: 480)
            }

            // Left headers + box
            HStack(alignment: .center, spacing: 0) {
                VStack(spacing: 0) {
                    Text(display(allelesB[0])).frame(height: boxHeight/2).monospaced()
                    Text(display(allelesB[1])).frame(height: boxHeight/2).monospaced()
                }
                .frame(width: leftGutter)

                ZStack {
                    // Outer border
                    RoundedRectangle(cornerRadius: boxCorner)
                        .stroke(.quaternary, lineWidth: boxStroke)

                    // Internal dividers
                    VStack(spacing: 0) {
                        Spacer()
                        Rectangle().fill(.quaternary).frame(height: boxStroke)
                        Spacer()
                    }
                    HStack(spacing: 0) {
                        Spacer()
                        Rectangle().fill(.quaternary).frame(width: boxStroke)
                        Spacer()
                    }

                    // Cells
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Cell(text: display(grid[0][0]))
                            Cell(text: display(grid[0][1]))
                        }
                        HStack(spacing: 0) {
                            Cell(text: display(grid[1][0]))
                            Cell(text: display(grid[1][1]))
                        }
                    }
                    .padding(boxStroke)
                }
                .frame(maxWidth: 480, maxHeight: boxHeight)
            }
        }
    }

    private func display(_ s: String) -> String { s.isEmpty ? " " : s }

    struct Cell: View {
        let text: String
        var body: some View {
            Text(text).monospaced()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - Logic

private func twoChars(_ s: String) -> [String] {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    let chars = trimmed.map { String($0) }
    let first = chars.indices.contains(0) ? chars[0] : ""
    let second = chars.indices.contains(1) ? chars[1] : ""
    return [first, second]
}

private func makeGridPartial(_ a: [String], _ b: [String]) -> [[String]] {
    func combineIfPossible(_ x: String, _ y: String) -> String {
        guard !x.isEmpty, !y.isEmpty else { return "" }
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
        [combineIfPossible(a[0], b[0]), combineIfPossible(a[1], b[0])],
        [combineIfPossible(a[0], b[1]), combineIfPossible(a[1], b[1])]
    ]
}

private func genotypeSummary(_ grid: [[String]]) -> [(String, Int, Double)] {
    let flat = grid.flatMap { $0 }.filter { !$0.isEmpty }
    guard !flat.isEmpty else { return [] }
    var counts: [String: Int] = [:]
    for g in flat { counts[g, default: 0] += 1 }
    let total = Double(flat.count)
    return counts
        .sorted { $0.key < $1.key }
        .map { (k, v) in (k, v, Double(v) / total) }
}

// base letter + dominant/recessive percentages (0–1)
private func traitOutcomeParts(_ items: [(String, Int, Double)])
-> (base: String, dom: Double, rec: Double)? {
    guard let firstGenotype = items.first?.0, let firstChar = firstGenotype.first else { return nil }
    let base = String(firstChar).uppercased()
    var dom = 0
    var rec = 0
    for (g, c, _) in items {
        let hasUpper = g.contains { String($0) == base }
        let hasLowerOnly = !hasUpper && g.contains { String($0) == base.lowercased() }
        if hasUpper { dom += c }
        else if hasLowerOnly { rec += c }
    }
    let total = max(dom + rec, 1)
    return (base, Double(dom)/Double(total), Double(rec)/Double(total))
}

private func formatPct1(_ p: Double) -> String {
    String(format: "%.1f%%", p * 100.0)
}

#Preview(windowStyle: .automatic) {
    ContentView()
}
