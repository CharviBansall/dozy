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

    /// Push today's plan to the watch. Uses application context, which queues the
    /// most recent value and delivers it whenever the watch wakes, even when the
    /// phone app is in the background.
    func push(from vm: SleepViewModel) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext(Self.payload(from: vm))
    }

    /// What the watch shows: the nap length and debt it always had, plus today's one thing.
    static func payload(from vm: SleepViewModel?) -> [String: Any] {
        let napSeconds = vm?.napLength ?? 0
        let napMinutes = napSeconds > 0 ? Int((napSeconds / 60).rounded()) : 20
        var payload: [String: Any] = [
            "napMinutes": napMinutes,
            "debtMinutes": Int(((vm?.totalDebt ?? 0) / 60).rounded()),
            "hasPlan": false,
        ]
        guard let vm, vm.nightsInWindow > 0, let action = vm.todayAction else { return payload }

        payload["hasPlan"] = true
        switch action {
        case .nap(let length, let earliest, let latest):
            payload["action"] = "nap"
            payload["napMinutes"] = Int((length / 60).rounded())
            payload["headline"] = "Take a \(SleepViewModel.duration(length)) nap"
            payload["detail"] = "Between \(SleepViewModel.clockText(earliest)) and \(SleepViewModel.clockText(latest))"
        case .bedtime(let plan):
            payload["action"] = "bedtime"
            payload["headline"] = "Be in bed by \(SleepViewModel.clockText(plan.bedtime))"
            payload["detail"] = vm.payoffText?.replacingOccurrences(of: " if you stick to the plan.", with: "")
                ?? "You’re all caught up"
        }
        return payload
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
            replyHandler(Self.payload(from: self.viewModel))
        }
    }
}
