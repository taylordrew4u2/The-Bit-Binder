import Foundation

@main
struct SiriCaptureRegression {
    static func main() throws {
        for content in ["", "  ", "\n\t\r", "\u{00A0}\u{2003}"] {
            do {
                _ = try SiriJokeCapture(content: content)
                preconditionFailure("Blank dictated content must be rejected")
            } catch SiriJokeCaptureError.emptyContent {
                // Expected: no transaction can begin with a blank request.
            }
        }

        let capture = try SiriJokeCapture(content: " \nThe airport coffee costs more than my flight.\nSecond line.  ")
        precondition(capture.content == "The airport coffee costs more than my flight.\nSecond line.")
        precondition(capture.title == "Airport Coffee Costs Flight", "Match the New Joke automatic title")
        let stopWords = try SiriJokeCapture(content: "the and")
        let punctuation = try SiriJokeCapture(content: "…")
        let unicode = try SiriJokeCapture(content: "  café 👩🏽‍🚀\n台詞  ")
        precondition(stopWords.title == "The And")
        precondition(punctuation.content == "…", "Do not discard nonblank material")
        precondition(unicode.content == "café 👩🏽‍🚀\n台詞")

        try SiriJokeCapture.validateStorage(isDurable: true, hasPendingRestore: false)
        do {
            try SiriJokeCapture.validateStorage(isDurable: false, hasPendingRestore: false)
            preconditionFailure("Temporary and read-only libraries must not claim a save")
        } catch SiriJokeCaptureError.persistentStoreUnavailable {
            // Expected, including the app's emergency in-memory fallback.
        }
        for isDurable in [true, false] {
            do {
                try SiriJokeCapture.validateStorage(isDurable: isDurable, hasPendingRestore: true)
                preconditionFailure("A staged restore would replace newly saved material")
            } catch SiriJokeCaptureError.restorePending {
                // Expected regardless of the current store's durability.
            }
        }

        var pending: [UUID: String] = [:]
        var durable: [UUID: String] = [:]
        var events: [String] = []
        for _ in 0..<2 {
            let identifier = try capture.save { request in
                events.append("insert")
                let identifier = UUID()
                pending[identifier] = request.content
                return identifier
            } commit: {
                events.append("save")
                durable.merge(pending) { _, new in new }
                pending.removeAll()
            } rollback: {
                preconditionFailure("A successful save must not roll back")
            }
            events.append("returned")
            precondition(durable[identifier] == capture.content, "Return only after storage succeeds")
        }
        precondition(durable.count == 2, "Repeated speech must create separate intentional captures")
        precondition(events == ["insert", "save", "returned", "insert", "save", "returned"])

        enum SaveFailure: Error { case diskFull }
        let previouslySaved = durable
        var didReturnIdentifier = false
        var didRollback = false
        do {
            _ = try capture.save { request in
                let identifier = UUID()
                pending[identifier] = request.content
                return identifier
            } commit: {
                throw SaveFailure.diskFull
            } rollback: {
                pending.removeAll()
                didRollback = true
            }
            didReturnIdentifier = true
        } catch SaveFailure.diskFull {
            precondition(didRollback, "The failed capture must be rolled back before propagating the error")
        }
        precondition(!didReturnIdentifier, "Failed saves must never produce success")
        precondition(pending.isEmpty && durable == previouslySaved, "A failure must preserve existing saved jokes")
        print("Siri capture regressions passed")
    }
}
