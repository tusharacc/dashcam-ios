//
//  VideoOverlayView.swift
//  dashcam
//
//  Created by Claude on 9/22/25.
//

import SwiftUI
import CoreLocation

struct VideoOverlayView: View {
    @State private var currentTime = Date()
    @State private var location: CLLocation?
    @State private var speed: Double = 0

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack {
            HStack {
                Spacer()

                // Move overlay to top-right to avoid collision
                VStack(alignment: .trailing, spacing: 1) {
                    // Time only
                    Text(currentTime, format: .dateTime.hour().minute().second())
                        .font(.caption)
                        .foregroundColor(.white)
                        .fontWeight(.medium)

                    // GPS and speed in one line
                    if let location = location {
                        HStack(spacing: 4) {
                            Text(String(format: "%.4f,%.4f", location.coordinate.latitude, location.coordinate.longitude))
                                .font(.caption2)
                                .foregroundColor(.white)

                            if speed > 0 {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                Text(String(format: "%.0f km/h", speed * 3.6))
                                    .font(.caption2)
                                    .foregroundColor(.white)
                            }
                        }
                    } else {
                        Text("GPS...")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
            }
            .padding(.top, 50) // Add top padding to avoid status bar overlap

            Spacer()
        }
        .padding(8)
        .onReceive(timer) { _ in
            currentTime = Date()
            updateLocationData()
        }
    }

    private func updateLocationData() {
        if let currentLocation = CameraService.shared.currentLocation {
            location = currentLocation
            speed = max(0, currentLocation.speed) // speed in m/s
        }
    }
}

#Preview {
    VideoOverlayView()
        .background(Color.gray)
}