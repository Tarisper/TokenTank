import Foundation

/// Top-N model aggregation (§3.5, REQ-TOP): sums per-model usage from the
/// history and ranks the models. Runs in the app only — the widget extension
/// reads the computed `modelTopByScope`.
public enum TopModels {
    /// Number of models kept per scope.
    public static let count = 3

    /// Aggregates per-model usage over a day window and returns the top models.
    ///
    /// Costs of one model in multiple currencies are not summed (no currency
    /// conversion): the cost is dropped and the model ranks by tokens.
    /// - Parameters:
    ///   - history: Usage history.
    ///   - fromDay: First day key (inclusive); `nil` — from the start.
    ///   - toDay: Last day key (inclusive); `nil` — to the end.
    ///   - count: Maximum number of models to return.
    /// - Returns: Aggregated `ModelUsage` entries ranked by consumed cost;
    ///   models without cost rank by tokens.
    public static func aggregate(
        history: [DailyUsage],
        fromDay: String? = nil,
        toDay: String? = nil,
        count: Int = TopModels.count
    ) -> [ModelUsage] {
        var totals: [String: (requests: Int, tokens: Int, cost: Decimal?, currency: String?, mixed: Bool)] = [:]
        for usage in history {
            if let fromDay, usage.localDay < fromDay { continue }
            if let toDay, usage.localDay > toDay { continue }
            for model in usage.models ?? [] {
                var total = totals[model.model, default: (0, 0, nil, nil, false)]
                total.requests += model.requests ?? 0
                total.tokens += model.tokens ?? 0
                if let cost = model.cost {
                    if total.mixed == false, total.cost == nil || total.currency == cost.currency {
                        total.cost = (total.cost ?? 0) + cost.amount
                        total.currency = cost.currency
                    } else if total.currency != cost.currency {
                        total.cost = nil
                        total.currency = nil
                        total.mixed = true
                    }
                }
                totals[model.model] = total
            }
        }
        let ranked = totals.sorted { lhs, rhs in
            switch (lhs.value.cost, rhs.value.cost) {
            case let (l?, r?):
                return l > r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.value.tokens > rhs.value.tokens
            }
        }
        return ranked.prefix(max(count, 0)).map { model, total in
            var cost: Money?
            if let amount = total.cost, let currency = total.currency {
                cost = Money(role: .cash, amount: amount, currency: currency)
            }
            return ModelUsage(
                model: model,
                requests: total.requests == 0 ? nil : total.requests,
                tokens: total.tokens == 0 ? nil : total.tokens,
                cost: cost
            )
        }
    }
}
