//
//  Config.swift
//  Example
//
//  Created by Alon Bar-el on 19/11/2025.
//

import Foundation

enum DecartConfig: Sendable {
	nonisolated static let apiKey = ProcessInfo.processInfo.environment["DECART_API_KEY"] ?? ""

	static let defaultPrompt: String = ProcessInfo.processInfo.environment["DECART_DEFAULT_PROMPT"]
		?? "Simpsons"
}
