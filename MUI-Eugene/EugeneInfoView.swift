// EugeneInfoView.swift
import SwiftUI

public struct EugeneInfoView: View {
    public let title: String
    public let traitA: String
    public let traitB: String
    public let traitC: String

    public init(title: String, traitA: String, traitB: String, traitC: String) {
        self.title = title
        self.traitA = traitA
        self.traitB = traitB
        self.traitC = traitC
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.title2, weight: .semibold))
                .padding(.top, 6)
            row(icon: "eye.fill", code: traitA)
            row(icon: "triangle.fill", code: traitB)
            row(icon: "paintpalette.fill", code: traitC)
        }
        .padding(16)
        .frame(width: 260)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func row(icon: String, code: String) -> some View {
        HStack {
            ZStack {
                Circle().fill(.thinMaterial)
                Image(systemName: icon).font(.system(size: 20, weight: .semibold))
            }
            .frame(width: 44, height: 44)

            Spacer(minLength: 12)

            Text(code)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospaced()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
