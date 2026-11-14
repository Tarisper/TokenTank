import Foundation
import TokenTankKit
import UserNotifications

/// UserNotifications shell (M5.3): all texts come from the string catalog;
/// the alert logic lives in `TokenTankKit.Alerting`.
final class NotificationService {
    /// Requests alert authorization once (non-blocking).
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Posts one notification per threshold transition (one per event, §5 M5).
    /// - Parameters:
    ///   - trigger: Transition produced by `ThresholdEvaluator`.
    ///   - accountLabel: Account label for the message body.
    func post(_ trigger: ThresholdEvaluator.Trigger, accountLabel: String) {
        let content = UNMutableNotificationContent()
        switch trigger.event {
        case .crossed:
            let valueText = formatted(trigger.value, threshold: trigger.threshold)
            let thresholdText = formatted(trigger.threshold.value, threshold: trigger.threshold)
            content.title = String(localized: "notify.lowBalance")
            content.body = String(localized: "notify.lowBalanceBody \(accountLabel) \(valueText) \(thresholdText)")
        case .rearmed:
            content.title = String(localized: "notify.restored")
            content.body = String(localized: "notify.restoredBody \(accountLabel)")
        case .none:
            return
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func formatted(_ amount: Decimal, threshold: Threshold) -> String {
        if let currency = threshold.currency {
            return amount.formatted(.currency(code: currency))
        }
        return amount.formatted()
    }
}
