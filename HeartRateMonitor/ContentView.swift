//
//  ContentView.swift
//  HeartRateMonitor
//
//  Created by Jason Luo on 7/8/22.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            CameraPreviewView()
            CameraControlView()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(DataModel())
    }
}
