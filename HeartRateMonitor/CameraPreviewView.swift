//
//  CameraPreviewView.swift
//  HeartRateMonitor
//
//  Created by Jason Luo on 7/19/22.
//

import SwiftUI

struct CameraPreviewView: View {
    @EnvironmentObject private var dataModel: DataModel
    
    var body: some View {
        GeometryReader { geometry in
            innerBody
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .border(.foreground, width: 1.0)
    }
    
    @ViewBuilder
    var innerBody: some View {
        switch dataModel.cameraStatus {
        case .uninitialized:
            Text("Ready to start camera...")
        case .missingDevice:
            Text("Could not find available camera/flashlight device")
        case .unauthorized:
            Text("Please give app access to the camera")
        case .stopped:
            Text("Camera stopped")
        case .running:
            if let image = dataModel.viewfinderImage {
                image
                    .resizable()
                    .scaledToFill()
            }
        }
    }
}

struct CameraPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        CameraPreviewView()
            .environmentObject(DataModel())
    }
}
