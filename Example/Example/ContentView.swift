//
//  ContentView.swift
//  Example
//
//  Created by Alon Bar-el on 03/11/2025.
//

import DecartSDK
import SwiftUI

struct ContentView: View {
	var body: some View {
		NavigationStack {
			List {
				Section(header: Text("Realtime")) {
					ForEach(RealtimeModel.allCases, id: \.self) { model in
						NavigationLink("Realtime - \(model.rawValue.capitalized)") {
							RealtimeView(realtimeModel: model)
						}
					}
				}

				Section(header: Text("Image Generation")) {
					ForEach(ImageModel.allCases, id: \.self) { model in
						NavigationLink("Image - \(model.rawValue)") {
							GenerateImageView(model: model)
						}
					}
				}

				Section(header: Text("Video Generation")) {
					ForEach(VideoModel.allCases, id: \.self) { model in
						NavigationLink("Video - \(model.rawValue)") {
							GenerateVideoView(model: model)
						}
					}
				}
			}
			.navigationTitle("Example")
		}
	}
}
