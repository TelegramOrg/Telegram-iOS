import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit

public func updatePremiumPromoConfigurationOnce(account: Account) -> Signal<Void, NoError> {
    return updatePremiumPromoConfigurationOnce(accountPeerId: account.peerId, postbox: account.postbox, network: account.network)
}

func updatePremiumPromoConfigurationOnce(accountPeerId: PeerId, postbox: Postbox, network: Network) -> Signal<Void, NoError> {
    return network.request(Api.functions.help.getPremiumPromo())
    |> map(Optional.init)
    |> `catch` { _ -> Signal<Api.help.PremiumPromo?, NoError> in
        return .single(nil)
    }
    |> mapToSignal { result -> Signal<Void, NoError> in
        guard let result = result else {
            return .complete()
        }
        return postbox.transaction { transaction -> Void in
            if case let .premiumPromo(_, _, _, _, _, apiUsers) = result {
                let parsedPeers = AccumulatedPeers(transaction: transaction, chats: [], users: apiUsers)
                updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: parsedPeers)
            }
            
            updatePremiumPromoConfiguration(transaction: transaction, { configuration -> PremiumPromoConfiguration in
                return PremiumPromoConfiguration(apiPremiumPromo: result)
            })
        }
    }
}

func managedPremiumPromoConfigurationUpdates(accountPeerId: PeerId, postbox: Postbox, network: Network) -> Signal<Void, NoError> {
    let poll = Signal<Void, NoError> { subscriber in
        return updatePremiumPromoConfigurationOnce(accountPeerId: accountPeerId, postbox: postbox, network: network).start(completed: {
            subscriber.putCompletion()
        })
    }
    return (poll |> then(.complete() |> suspendAwareDelay(10.0 * 60.0 * 60.0, queue: Queue.concurrentDefaultQueue()))) |> restart
}

private func currentPremiumPromoConfiguration(transaction: Transaction) -> PremiumPromoConfiguration {
    if let entry = transaction.getPreferencesEntry(key: PreferencesKeys.premiumPromo)?.get(PremiumPromoConfiguration.self) {
        return entry
    } else {
        return PremiumPromoConfiguration.defaultValue
    }
}

private func updatePremiumPromoConfiguration(transaction: Transaction, _ f: (PremiumPromoConfiguration) -> PremiumPromoConfiguration) {
    let current = currentPremiumPromoConfiguration(transaction: transaction)
    let updated = f(current)
    if updated != current {
        transaction.setPreferencesEntry(key: PreferencesKeys.premiumPromo, value: PreferencesEntry(updated))
    }
}

private extension PremiumPromoConfiguration {
    init(apiPremiumPromo: Api.help.PremiumPromo) {
        switch apiPremiumPromo {
            case let .premiumPromo(statusText, statusEntities, videoSections, videoFiles, options, _):
                self.status = statusText
                self.statusEntities = messageTextEntitiesFromApiEntities(statusEntities)

                var videos: [String: TelegramMediaFile] = [:]
                for (key, document) in zip(videoSections, videoFiles) {
                    if let file = telegramMediaFileFromApiDocument(document, altDocuments: []) {
                        videos[key] = file
                    }
                }
                self.videos = videos
            
                var productOptions: [PremiumProductOption] = []
                for option in options {
                    if case let .premiumSubscriptionOption(flags, transaction, months, currency, amount, botUrl, storeProduct) = option {
                        productOptions.append(PremiumProductOption(isCurrent: (flags & (1 << 1)) != 0, months: months, currency: currency, amount: amount, botUrl: botUrl, transactionId: transaction, availableForUpgrade: (flags & (1 << 2)) != 0, storeProductId: storeProduct))
                    }
                }
                self.premiumProductOptions = productOptions
        }
    }
}
