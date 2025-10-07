//
//  WelcomeView.swift
//  MUI-Eugene
//
//  Created by Lukman Aščić on 07.10.2025.
//

import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        VStack {
            Text("Introduction")
            Button("Start") {
                appState.isImmersive.toggle()
            }
        }
        .frame(width: 500, height: 300)
        .padding()
        .glassBackgroundEffect()
    }
}

#Preview {
    WelcomeView()
        .environment(AppState())
}
