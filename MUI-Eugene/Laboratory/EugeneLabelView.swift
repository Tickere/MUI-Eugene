//
//  EugeneLabelView.swift
//  MUI-Eugene
//
//  Created by Lukman Aščić on 07.10.2025.
//

import SwiftUI

struct EugeneLabelView: View {
    let codeTitle: String
    let generation: Int
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(codeTitle)
                Text("\(generation). Generation")
            }
            Spacer()
        }
        .frame(maxWidth: 200)
        .padding()
        .glassBackgroundEffect(in: .rect(cornerRadius: 14))
    }
}

#Preview {
    EugeneLabelView(codeTitle: "AATTCG", generation: 1)
}
