import StoreKit
import AppShell

public class IAPAdapter: NSObject, ShellAdapter, SKProductsRequestDelegate, SKPaymentTransactionObserver {

    private weak var bridge: JSBridge?
    private var purchaseCallback: (([String: Any]) -> Void)?
    private var priceCallbacks: [([String: Any]) -> Void] = []
    private var cachedProduct: SKProduct?

    public override init() {}

    public func register(bridge: JSBridge) {
        self.bridge = bridge
        SKPaymentQueue.default().add(self)

        bridge.registerHandler(module: "iap", action: "getPrice") { [weak self] params, callback in
            guard let self = self else { return }
            guard let productId = params["productId"] as? String else {
                callback(["ok": false, "error": "missing productId"])
                return
            }
            if let product = self.cachedProduct, product.productIdentifier == productId {
                callback(["ok": true, "price": self.formatted(product)])
                return
            }
            self.priceCallbacks.append(callback)
            let req = SKProductsRequest(productIdentifiers: [productId])
            req.delegate = self
            req.start()
        }

        bridge.registerHandler(module: "iap", action: "purchase") { [weak self] params, callback in
            guard let self = self else { return }
            guard SKPaymentQueue.canMakePayments() else {
                callback(["ok": false, "error": "payments_disabled"])
                return
            }
            guard let productId = params["productId"] as? String else {
                callback(["ok": false, "error": "missing productId"])
                return
            }
            self.purchaseCallback = callback
            if let product = self.cachedProduct, product.productIdentifier == productId {
                SKPaymentQueue.default().add(SKPayment(product: product))
            } else {
                let req = SKProductsRequest(productIdentifiers: [productId])
                req.delegate = self
                req.start()
            }
        }

        bridge.registerHandler(module: "iap", action: "restore") { [weak self] _, callback in
            self?.purchaseCallback = callback
            SKPaymentQueue.default().restoreCompletedTransactions()
        }

        // Check if user already owns the product (fires iap.unlocked event if so)
        bridge.registerHandler(module: "iap", action: "checkUnlock") { [weak self] params, callback in
            guard let productId = params["productId"] as? String else {
                callback(["ok": false])
                return
            }
            Task { [weak self] in
                var found = false
                for await result in Transaction.currentEntitlements {
                    if case .verified(let tx) = result, tx.productID == productId {
                        found = true
                        await tx.finish()
                    }
                }
                DispatchQueue.main.async {
                    if found {
                        self?.bridge?.sendEvent(name: "iap.unlocked", data: ["restored": true])
                    }
                    callback(["ok": true, "found": found])
                }
            }
        }
    }

    private func formatted(_ product: SKProduct) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = product.priceLocale
        return f.string(from: product.price) ?? "\(product.price)"
    }

    private func deliverUnlock(transactionId: String, restored: Bool) {
        // Try callback first, fall back to bridge event (handles pending transactions on launch)
        if let cb = purchaseCallback {
            cb(["ok": true, "restored": restored, "transactionId": transactionId])
            purchaseCallback = nil
        } else {
            bridge?.sendEvent(name: "iap.unlocked", data: ["restored": restored, "transactionId": transactionId])
        }
    }

    // MARK: - SKProductsRequestDelegate

    public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        DispatchQueue.main.async {
            if let product = response.products.first {
                self.cachedProduct = product
                let price = self.formatted(product)
                for cb in self.priceCallbacks { cb(["ok": true, "price": price]) }
                self.priceCallbacks.removeAll()
                if self.purchaseCallback != nil {
                    SKPaymentQueue.default().add(SKPayment(product: product))
                }
            } else {
                let ids = response.invalidProductIdentifiers
                let err = ids.isEmpty ? "product_not_found" : "invalid_ids:\(ids.joined(separator: ","))"
                for cb in self.priceCallbacks { cb(["ok": false, "error": err]) }
                self.priceCallbacks.removeAll()
                self.purchaseCallback?(["ok": false, "error": err])
                self.purchaseCallback = nil
            }
        }
    }

    public func request(_ request: SKRequest, didFailWithError error: Error) {
        DispatchQueue.main.async {
            let msg = error.localizedDescription
            for cb in self.priceCallbacks { cb(["ok": false, "error": msg]) }
            self.priceCallbacks.removeAll()
            self.purchaseCallback?(["ok": false, "error": msg])
            self.purchaseCallback = nil
        }
    }

    // MARK: - SKPaymentTransactionObserver

    public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for tx in transactions {
            switch tx.transactionState {
            case .purchased:
                queue.finishTransaction(tx)
                DispatchQueue.main.async {
                    self.deliverUnlock(transactionId: tx.transactionIdentifier ?? "", restored: false)
                }
            case .restored:
                queue.finishTransaction(tx)
                DispatchQueue.main.async {
                    self.deliverUnlock(transactionId: tx.original?.transactionIdentifier ?? "", restored: true)
                }
            case .failed:
                queue.finishTransaction(tx)
                DispatchQueue.main.async {
                    let cancelled = (tx.error as? SKError)?.code == .paymentCancelled
                    self.purchaseCallback?(["ok": false, "error": cancelled ? "cancelled" : (tx.error?.localizedDescription ?? "failed")])
                    self.purchaseCallback = nil
                }
            case .deferred, .purchasing:
                break
            @unknown default:
                break
            }
        }
    }

    public func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        DispatchQueue.main.async {
            // Only fires if no restored transactions came through updatedTransactions
            self.purchaseCallback?(["ok": false, "restored": false, "error": "no_purchases"])
            self.purchaseCallback = nil
        }
    }

    public func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        DispatchQueue.main.async {
            self.purchaseCallback?(["ok": false, "error": error.localizedDescription])
            self.purchaseCallback = nil
        }
    }
}
