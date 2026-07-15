import Foundation

enum AnalyticsEvent: Sendable {
    case impression(TrackingContext)
    case tap(TrackingContext)
    case addToCart(productID: String, requestID: String)
    case contractIssue(HomeContractIssue)
}

actor AnalyticsTracker {
    private let eventLimit: Int
    private var impressions = Set<String>()
    private var impressionOrder: [String] = []
    private var contractIssues: [HomeContractIssue] = []

    init(eventLimit: Int = 200) {
        self.eventLimit = eventLimit
    }

    func track(_ event: AnalyticsEvent) {
        switch event {
        case .impression(let context):
            let key = [context.requestID, context.sectionID, context.itemID ?? "section"].joined(separator: ":")
            guard impressions.insert(key).inserted else { return }
            impressionOrder.append(key)
            if impressionOrder.count > eventLimit {
                let overflow = impressionOrder.count - eventLimit
                let expired = impressionOrder.prefix(overflow)
                impressions.subtract(expired)
                impressionOrder.removeFirst(overflow)
            }
        case .contractIssue(let issue):
            contractIssues.append(issue)
            if contractIssues.count > eventLimit {
                contractIssues.removeFirst(contractIssues.count - eventLimit)
            }
        case .tap, .addToCart:
            break
        }
        // A production adapter would enqueue, batch and retry without blocking UI.
    }

    func recordedContractIssues() -> [HomeContractIssue] {
        contractIssues
    }

    nonisolated func enqueueContractIssues(_ issues: [HomeContractIssue]) {
        guard !issues.isEmpty else { return }
        Task {
            await recordContractIssues(issues)
        }
    }

    private func recordContractIssues(_ issues: [HomeContractIssue]) {
        issues.forEach {
            track(.contractIssue($0))
        }
    }
}
