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
		NavigationView {
			List {
				Section(header: Text("Realtime")) {
					ForEach(RealtimeModel.allCases, id: \.self) { model in
						NavigationLink(
							destination: RealtimeView(
								realtimeModel: model
							)
						) {
							Text("Realtime - \(model.rawValue.capitalized)")
						}
					}
				}

				Section(header: Text("Image Generation")) {
					ForEach(ImageModel.allCases, id: \.self) { model in
						NavigationLink(
							destination: GenerateImageView(
								model: model
							)
						) {
							Text("Image - \(model.rawValue)")
						}
					}
				}

				Section(header: Text("Video Generation")) {
					ForEach(VideoModel.allCases, id: \.self) { model in
						NavigationLink(
							destination: GenerateVideoView(
								model: model
							)
						) {
							Text("Video - \(model.rawValue)")
						}
					}
				}
			}
			.navigationBarTitle("Example")
		}
	}
}
