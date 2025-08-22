//
//  AffirmationDataProtocol.swift
//  SelfLie
//
//  Created by lw on 8/22/25.
//

import Foundation

protocol AffirmationDataProtocol: AnyObject, Observable {
    var currentStep: Int { get set }
    var goal: String { get set }
    var reason: String { get set }
    var affirmationText: String { get set }
    var audioURL: URL? { get set }
    var wordTimings: [WordTiming] { get set }
    var progress: Double { get }
    
    func generateAffirmation()
    func nextStep()
    func reset()
}