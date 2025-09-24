//
//  PaywallController.swift
//  SelfLie
//
//  Created by Codex on 2025-??.
//

import Foundation
import Observation

@MainActor
@Observable
final class PaywallController {
    enum Context {
        case createAffirmation
        case practiceAffirmation
        case general
    }
    
    var isPresented = false
    var context: Context = .general
    
    @ObservationIgnored
    var pendingAction: (() -> Void)?
    
    func present(context: Context, pendingAction: (() -> Void)? = nil) {
        self.context = context
        self.pendingAction = pendingAction
        isPresented = true
    }
    
    func dismiss() {
        isPresented = false
    }
    
    func reset() {
        context = .general
        pendingAction = nil
    }
}
