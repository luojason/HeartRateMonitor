//
//  DataModel.swift
//  HeartRateMonitor
//
//  Created by Jason Luo on 7/17/22.
//

import Foundation
import AVFoundation
import SwiftUI

final class DataModel: ObservableObject {
    @Published var viewfinderImage: Image?
    @Published var cameraStatus: Camera.Status = .uninitialized
    
    let camera = Camera()

    init() {
        // synchronize camera status with published property
        camera.$status
            .receive(on: DispatchQueue.main)
            .assign(to: &$cameraStatus)
        
        // launch task to update preview image with video output
        Task {
            await managePreviewImage()
        }
    }
    
    private func managePreviewImage() async {
        for await image in camera.previewStream {
            Task { @MainActor in
                viewfinderImage = image.image
            }
        }
    }
}

fileprivate extension CIImage {
    var image: Image? {
        let ciContext = CIContext()
        guard let cgImage = ciContext.createCGImage(self, from: self.extent) else { return nil }
        return Image(decorative: cgImage, scale: 1, orientation: .up)
    }
}
