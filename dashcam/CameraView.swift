//
//  CameraView.swift
//  dashcam
//
//  Created by Tushar Saurabh on 6/24/25.
//
import SwiftUI
import AVFoundation

struct CameraView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> some UIViewController {
        return CameraViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
        // No updates needed for now
    }
}

