//
//  Phoneconnector.swift
//  dozy
//
//  Created by Charvi Bansal on 6/10/26.
//

import Foundation
import WatchConnectivity
import Combine


/// Phone side of the bridge. Replies to the watch's request with the current
/// nap recommendation + debt, pulled from the shared view model.
@MainActor
final class PhoneConnector: NSObject, ObservableObject {

    static let shared = PhoneConnector()

    /// Set this from the app so the responder can read live values.
    weak var viewModel: SleepViewModel?

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func activate() { /* touching shared triggers init */ }

    /// Push the latest nap/debt to the watch. Uses application context, which
    /// queues the most recent value and delivers it whenever the watch wakes —
    /// works in the simulator and even when the phone app is backgrounded.
    func push(napMinutes: Int, debtMinutes: Int) {
        guard WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext([
            "napMinutes": napMinutes,
            "debtMinutes": debtMinutes
        ])
    }
}

extension PhoneConnector: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String : Any],
                             replyHandler: @escaping ([String : Any]) -> Void) {
        Task { @MainActor in
            // If the VM hasn't loaded yet (napLength still 0), load it first so
            // we don't reply with the fallback.
            if let vm = self.viewModel, vm.napLength == 0 {
                await vm.load()
            }
            let napSeconds = self.viewModel?.napLength ?? 0
            let debtSeconds = self.viewModel?.totalDebt ?? 0
            let napMin = napSeconds > 0 ? Int((napSeconds / 60).rounded()) : 20
            let debtMin = Int((debtSeconds / 60).rounded())
            replyHandler(["napMinutes": napMin, "debtMinutes": debtMin])
        }
    }
}
