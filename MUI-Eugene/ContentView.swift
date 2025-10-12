import SwiftUI
import RealityKit
import RealityKitContent

// Darker gray for readability
private let combineTint: Color = Color.gray.opacity(0.85)
private let combineFont: Font  = .title2.weight(.semibold)

struct ContentView: View {
    @State private var showCombine = false

    var body: some View {
        PunnettSquareTabs(onCompletenessChange: { showCombine = $0 })
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .ornament(
                visibility: showCombine ? .visible : .hidden,
                attachmentAnchor: .scene(.bottom)
            ) {
                Button("Combine") { /* combine action */ }
                    .font(combineFont)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.extraLarge)
                    .tint(combineTint)              // darker tint
                    .padding(.horizontal, 40)
                    .padding(.vertical, 8)
                    .shadow(radius: 8, y: 4)
            }
    }
}

// MARK: - Tabs
struct PunnettSquareTabs: View {
    let onCompletenessChange: (Bool) -> Void

    var body: some View {
        TabView {
            PunnettSquareView(defaultGenotype: "", traitName: "Eyes", onCompletenessChange: onCompletenessChange)
                .tabItem { Label("Eyes", systemImage: "eye") }
            PunnettSquareView(defaultGenotype: "", traitName: "Horns", onCompletenessChange: onCompletenessChange)
                .tabItem { Label("Horns", systemImage: "triangle") }
            PunnettSquareView(defaultGenotype: "", traitName: "Colour", onCompletenessChange: onCompletenessChange)
                .tabItem { Label("Colour", systemImage: "paintpalette") }
        }
    }
}

// MARK: - Punnett Square
struct PunnettSquareView: View {
    @State private var parentA: String
    @State private var parentB: String
    private let traitName: String
    private let onCompletenessChange: (Bool) -> Void

    init(defaultGenotype: String, traitName: String, onCompletenessChange: @escaping (Bool) -> Void) {
        _parentA = State(initialValue: defaultGenotype)
        _parentB = State(initialValue: defaultGenotype)
        self.traitName = traitName
        self.onCompletenessChange = onCompletenessChange
    }

    private var headersA: [String] { twoChars(parentA) }
    private var headersB: [String] { twoChars(parentB) }
    private var grid: [[String]] { makeGridPartial(headersA, headersB) }
    private var percentages: (base: String, dom: Double, rec: Double)? {
        traitOutcomeParts(genotypeSummary(grid))
    }
    private var hasCompleteInputs: Bool {
        headersA.allSatisfy { !$0.isEmpty } && headersB.allSatisfy { !$0.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
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

                // Punnett Square
                PunnettGridView(allelesA: headersA, allelesB: headersB, grid: grid)
                    .frame(height: 200)

                // Outcome
                VStack(alignment: .leading, spacing: 14) {
                    Text("Outcome").font(.title.weight(.semibold))
                    HStack(spacing: 16) {
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
            }
            .padding(16)
        }
        .onAppear { onCompletenessChange(hasCompleteInputs) }
        .onChange(of: parentA) { _, _ in onCompletenessChange(hasCompleteInputs) }
        .onChange(of: parentB) { _, _ in onCompletenessChange(hasCompleteInputs) }
    }
}

// MARK: - Outcome Card
struct OutcomeCard: View {
    let title: String
    let percentText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.body.weight(.medium))
            Text(percentText).font(.title2.weight(.medium)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.regularMaterial))
    }
}

// MARK: - Punnett Grid
struct PunnettGridView: View {
    let allelesA: [String], allelesB: [String], grid: [[String]]

    private let boxCorner: CGFloat = 16
    private let boxStroke: CGFloat = 2
    private let boxHeight: CGFloat = 160
    private let leftGutter: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            let boxWidth = geo.size.width - leftGutter

            VStack(alignment: .leading, spacing: 10) {
                // Top headers
                HStack(spacing: 0) {
                    Spacer().frame(width: leftGutter)
                    HStack(spacing: 0) {
                        Text(display(allelesA[0])).frame(maxWidth: .infinity).monospaced()
                        Text(display(allelesA[1])).frame(maxWidth: .infinity).monospaced()
                    }
                }

                // Left headers + grid
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Text(display(allelesB[0])).frame(height: boxHeight/2).monospaced()
                        Text(display(allelesB[1])).frame(height: boxHeight/2).monospaced()
                    }
                    .frame(width: leftGutter)

                    ZStack {
                        RoundedRectangle(cornerRadius: boxCorner).stroke(.quaternary, lineWidth: boxStroke)
                        VStack(spacing: 0) { Spacer(); Rectangle().fill(.quaternary).frame(height: boxStroke); Spacer() }
                        HStack(spacing: 0) { Spacer(); Rectangle().fill(.quaternary).frame(width: boxStroke); Spacer() }
                        VStack(spacing: 0) {
                            HStack(spacing: 0) { Cell(text: display(grid[0][0])); Cell(text: display(grid[0][1])) }
                            HStack(spacing: 0) { Cell(text: display(grid[1][0])); Cell(text: display(grid[1][1])) }
                        }
                        .padding(boxStroke)
                    }
                    .frame(width: boxWidth, height: boxHeight)
                }
            }
        }
        .frame(height: boxHeight + 44)
    }

    private func display(_ s: String) -> String { s.isEmpty ? " " : s }

    struct Cell: View {
        let text: String
        var body: some View {
            Text(text).monospaced().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Logic
private func twoChars(_ s: String) -> [String] {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    let chars = trimmed.map { String($0) }
    return [chars.indices.contains(0) ? chars[0] : "", chars.indices.contains(1) ? chars[1] : ""]
}

private func makeGridPartial(_ a: [String], _ b: [String]) -> [[String]] {
    func combineIfPossible(_ x: String, _ y: String) -> String {
        guard !x.isEmpty, !y.isEmpty else { return "" }
        let sorted = [x, y].sorted {
            if $0 == $1 { return false }
            let l = $0.uppercased(), r = $1.uppercased()
            return l == r ? $0 < $1 : l < r
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
    return counts.sorted { $0.key < $1.key }.map { (k, v) in (k, v, Double(v)/total) }
}

private func traitOutcomeParts(_ items: [(String, Int, Double)]) -> (base: String, dom: Double, rec: Double)? {
    guard let g0 = items.first?.0, let c0 = g0.first else { return nil }
    let base = String(c0).uppercased()
    var dom = 0, rec = 0
    for (g, c, _) in items {
        let hasUpper = g.contains { String($0) == base }
        let hasLowerOnly = !hasUpper && g.contains { String($0) == base.lowercased() }
        if hasUpper { dom += c } else if hasLowerOnly { rec += c }
    }
    let tot = max(dom + rec, 1)
    return (base, Double(dom)/Double(tot), Double(rec)/Double(tot))
}

private func formatPct1(_ p: Double) -> String {
    String(format: "%.1f%%", p * 100.0)
}
