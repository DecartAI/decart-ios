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
			List(RealtimeModel.allCases, id: \.self) { model in
				NavigationLink(
					destination: RealtimeView(
						realtimeModel: model
					)
				) {
					Text("Realtime - \(model.rawValue.capitalized)")
				}
			}
			.navigationBarTitle("Example")
		}
	}
}
