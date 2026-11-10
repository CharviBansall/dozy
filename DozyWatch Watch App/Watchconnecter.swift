//
//  Watchconnecter.swift
//  dozy
//
//  Created by Charvi Bansal on 6/10/26.
//

import Foundation
import WatchConnectivity
import Combine
/// Watch side of the bridge. Asks the phone for the current nap recommendation
/// and holds the latest value for the UI. Falls back to a default if the phone
/// is unreachable, so the watch app still works on its own.
@MainActor
final class WatchConnector: NSObject, ObservableObject {

    static let shared = WatchConnector()

    @Published var napMinutes: Int = 20      // sensible default until phone replies
    @Published var debtMinutes: Int = 0
    @Published var reachable = false
    @Published var hasLoaded = false          // true once phone replies or we time out

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Ask the phone for the latest recommendation.
    func refresh() {
        // Whatever happens, don't show the loading screen forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.hasLoaded = true
        }

        guard WCSession.default.activationState == .activated,
              WCSession.default.isReachable else {
            reachable = false
            return
        }
        WCSession.default.sendMessage(["request": "nap"], replyHandler: { reply in
            Task { @MainActor in
                if let nap = reply["napMinutes"] as? Int { self.napMinutes = nap }
                if let debt = reply["debtMinutes"] as? Int { self.debtMinutes = debt }
                self.hasLoaded = true
            }
        }, errorHandler: { _ in
            // Keep the existing/default value on error; timeout will reveal the UI.
        })
    }
}

extension WatchConnector: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            self.reachable = (session.activationState == .activated && session.isReachable)
            // Read any context the phone already pushed before we were listening.
            let ctx = session.receivedApplicationContext
            if let nap = ctx["napMinutes"] as? Int { self.napMinutes = nap }
            if let debt = ctx["debtMinutes"] as? Int { self.debtMinutes = debt }
            if !ctx.isEmpty { self.hasLoaded = true }
            self.refresh()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.reachable = session.isReachable
            if session.isReachable { self.refresh() }
        }
    }

    /// Primary path: the phone pushes its latest nap/debt here. Works in the
    /// simulator and when the phone app is backgrounded.
    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String : Any]) {
        Task { @MainActor in
            if let nap = applicationContext["napMinutes"] as? Int { self.napMinutes = nap }
            if let debt = applicationContext["debtMinutes"] as? Int { self.debtMinutes = debt }
            self.hasLoaded = true
        }
    }
}
