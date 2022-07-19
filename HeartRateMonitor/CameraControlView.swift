//
//  CameraControlView.swift
//  HeartRateMonitor
//
//  Created by Jason Luo on 7/19/22.
//

import SwiftUI

struct CameraControlView: View {
    @EnvironmentObject private var dataModel: DataModel

    var body: some View {
        innerBody
            .buttonStyle(.bordered)
    }
    
    @ViewBuilder
    private var innerBody: some View {
        switch dataModel.cameraStatus {
        case .missingDevice, .unauthorized:
            Button("Start Camera") {}
                .disabled(true)
        case .stopped, .uninitialized:
            Button("Start Camera") {
                Task {
                    await dataModel.camera.start()
                }
            }
        case .running:
            Button("Stop Camera", role: .cancel) {
                Task {
                    await dataModel.camera.stop()
                }
            }
        }
    }
}

struct CameraControlView_Previews: PreviewProvider {
    static var previews: some View {
        CameraControlView()
            .environmentObject(DataModel())
    }
}
