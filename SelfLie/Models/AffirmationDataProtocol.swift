//
//  AffirmationDataProtocol.swift
//  SelfLie
//
//  Created by lw on 8/22/25.
//

import Foundation

@MainActor
protocol AffirmationDataProtocol: AnyObject, Observable {
    var currentStep: Int { get set }
    var goal: String { get set }
    var reason: String { get set }
    var affirmationText: String { get set }
    var audioURL: URL? { get set }
    var wordTimings: [WordTiming] { get set }
    var progress: Double { get }
    
    // Foundation Models generation state
    var isGeneratingAffirmation: Bool { get }
    var generationError: AffirmationError? { get }
    var canUseFoundationModels: Bool { get }
    var generationStatusMessage: String { get }
    var canRetryGeneration: Bool { get }
    
    // Original synchronous method (kept for compatibility)
    func generateAffirmation()
    
    // New async method for Foundation Models generation
    @discardableResult
    func generateAffirmationAsync() async throws -> String
    func retryGeneration() async throws
    func prewarmAISession()
    
    func nextStep()
    func reset()
}