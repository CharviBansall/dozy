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
    /// "nap" or "bedtime": today's one thing, as the phone worked it out.
    @Published var action = "nap"
    /// "Be in bed by 10:45 PM" or "Take a 20 min nap".
    @Published var headline = ""
    /// The line under the headline: the nap window, or when the debt is cleared.
    @Published var detail = ""
    /// False until the phone has sleep data to plan from.
    @Published var hasPlan = false
    @Published var reachable = false
    @Published var hasLoaded = false          // true once phone replies or we time out

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Takes whatever the phone sent. Older phone builds only send the first two.
    private func apply(_ payload: [String: Any]) {
        if let nap = payload["napMinutes"] as? Int { napMinutes = nap }
        if let debt = payload["debtMinutes"] as? Int { debtMinutes = debt }
        if let action = payload["action"] as? String { self.action = action }
        if let headline = payload["headline"] as? String { self.headline = headline }
        if let detail = payload["detail"] as? String { self.detail = detail }
        if let hasPlan = payload["hasPlan"] as? Bool { self.hasPlan = hasPlan }
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
                self.apply(reply)
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
            self.apply(ctx)
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
            self.apply(applicationContext)
            self.hasLoaded = true
        }
    }
}
