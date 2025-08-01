import Foundation
import Postbox
import TelegramApi
import SwiftSignalKit


public func loadedPeerFromMessage(account: Account, peerId: PeerId, messageId: MessageId) -> Signal<Peer?, NoError> {
    let accountPeerId = account.peerId
    return account.postbox.transaction { transaction -> Signal<Peer?, NoError> in
        if let peer = transaction.getPeer(peerId) {
            if let user = peer as? TelegramUser {
                if let accessHash = user.accessHash, accessHash.value != 0 {
                    return .single(user)
                } else {
                    let messageSignal: Signal<Api.messages.Messages?, NoError>?
                    if messageId.peerId.namespace == Namespaces.Peer.CloudUser || messageId.peerId.namespace == Namespaces.Peer.CloudGroup {
                        messageSignal = account.network.request(Api.functions.messages.getMessages(id: [Api.InputMessage.inputMessageID(id: messageId.id)]))
                            |> map(Optional.init)
                            |> `catch` { _ -> Signal<Api.messages.Messages?, NoError> in
                                return .single(nil)
                            }
                    } else if messageId.peerId.namespace == Namespaces.Peer.CloudChannel, let channelPeer = transaction.getPeer(messageId.peerId), let inputChannel = apiInputChannel(channelPeer) {
                        messageSignal = account.network.request(Api.functions.channels.getMessages(channel: inputChannel, id: [Api.InputMessage.inputMessageID(id: messageId.id)]))
                            |> map(Optional.init)
                            |> `catch` { _ -> Signal<Api.messages.Messages?, NoError> in
                                return .single(nil)
                            }
                    } else {
                        messageSignal = nil
                    }
                    
                    if let messageSignal = messageSignal {
                        return messageSignal |> mapToSignal { result -> Signal<Peer?, NoError> in
                            return account.postbox.transaction { transaction -> Peer? in
                                if let result = result {
                                    let apiUsers: [Api.User]
                                    switch result {
                                    case let .messages(_, _, users):
                                        apiUsers = users
                                    case let .messagesSlice(_, _, _, _, _, _, _, users):
                                        apiUsers = users
                                    case let .channelMessages(_, _, _, _, _, _, _, users):
                                        apiUsers = users
                                    case .messagesNotModified:
                                        apiUsers = []
                                    }
                                    
                                    let parsedPeers = AccumulatedPeers(users: apiUsers)
                                    updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: parsedPeers)
                                    
                                    if let peer = transaction.getPeer(peerId) {
                                        return peer
                                    }
                                }
                                return nil
                            }
                        }
                    } else {
                        return .single(nil)
                    }
                }
            } else {
                return .single(peer)
            }
        } else {
            return .single(nil)
        }
    } |> switchToLatest
}
