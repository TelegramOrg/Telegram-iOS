
import TelegramApi
import SwiftSignalKit
import Postbox
import Foundation

public enum InternalUpdaterError {
    case generic
    case xmlLoad
    case archiveLoad
}

public func requestUpdatesXml(account: Account, source: String) -> Signal<Data, InternalUpdaterError> {
    return TelegramEngine(account: account).peers.resolvePeerByName(name: source, referrer: nil)
        |> castError(InternalUpdaterError.self)
        |> mapToSignal { result -> Signal<Peer?, InternalUpdaterError> in
            switch result {
            case .progress:
                return .never()
            case let .result(peer):
                return .single(peer?._asPeer())
            }
        }
        |> mapToSignal { peer -> Signal<Data, InternalUpdaterError> in
            if let peer = peer, let inputPeer = apiInputPeer(peer) {
                return account.network.request(Api.functions.messages.getHistory(peer: inputPeer, offsetId: 0, offsetDate: 0, addOffset: 0, limit: 1, maxId: Int32.max, minId: 0, hash: 0))
                    |> retryRequest
                    |> castError(InternalUpdaterError.self)
                    |> mapToSignal { result in
                        switch result {
                        case let .channelMessages(_, _, _, _, apiMessages, _, apiChats, apiUsers):
                            if let apiMessage = apiMessages.first, let storeMessage = StoreMessage(apiMessage: apiMessage, accountPeerId: account.peerId, peerIsForum: peer.isForum) {
                                
                                var peers: [PeerId: Peer] = [:]
                                for chat in apiChats {
                                    if let groupOrChannel = parseTelegramGroupOrChannel(chat: chat) {
                                        peers[groupOrChannel.id] = groupOrChannel
                                    }
                                }
                                for user in apiUsers {
                                    let telegramUser = TelegramUser(user: user)
                                    peers[telegramUser.id] = telegramUser
                                }
                                
                                if let message = locallyRenderedMessage(message: storeMessage, peers: peers), let media = message.media.first as? TelegramMediaFile {
                                    return Signal { subscriber in
                                        let fetchDispsable = fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: .other, userContentType: .other, reference: MediaResourceReference.media(media: AnyMediaReference.message(message: MessageReference(message), media: media), resource: media.resource)).start()
                                        
                                        let dataDisposable = account.postbox.mediaBox.resourceData(media.resource, option: .complete(waitUntilFetchStatus: true)).start(next: { data in
                                            if data.complete {
                                                if let data = try? Data(contentsOf: URL.init(fileURLWithPath: data.path)) {
                                                    subscriber.putNext(data)
                                                    subscriber.putCompletion()
                                                } else {
                                                    subscriber.putError(.xmlLoad)
                                                }
                                            }
                                        })
                                        return ActionDisposable {
                                            fetchDispsable.dispose()
                                            dataDisposable.dispose()
                                        }
                                    }
                                }
                            }
                        default:
                            break
                        }
                        return .fail(.xmlLoad)
                }
            } else {
                return .fail(.xmlLoad)
            }
        }
}

public enum AppUpdateDownloadResult {
    case started(Int)
    case progress(Int, Int)
    case finished(String)
}

public func downloadAppUpdate(account: Account, source: String, messageId: Int32) -> Signal<AppUpdateDownloadResult, InternalUpdaterError> {
    return TelegramEngine(account: account).peers.resolvePeerByName(name: source, referrer: nil)
        |> castError(InternalUpdaterError.self)
        |> mapToSignal { result -> Signal<Peer?, InternalUpdaterError> in
            switch result {
            case .progress:
                return .never()
            case let .result(peer):
                return .single(peer?._asPeer())
            }
        }
        |> mapToSignal { peer in
            if let peer = peer, let inputChannel = apiInputChannel(peer) {
                return account.network.request(Api.functions.channels.getMessages(channel: inputChannel, id: [Api.InputMessage.inputMessageID(id: messageId)]))
                    |> retryRequest
                    |> castError(InternalUpdaterError.self)
                    |> mapToSignal { messages in
                        switch messages {
                        case let .channelMessages(_, _, _, _, apiMessages, _, apiChats, apiUsers):
                            
                            var peers: [PeerId: Peer] = [:]
                            for chat in apiChats {
                                if let groupOrChannel = parseTelegramGroupOrChannel(chat: chat) {
                                    peers[groupOrChannel.id] = groupOrChannel
                                }
                            }
                            for user in apiUsers {
                                let telegramUser = TelegramUser(user: user)
                                peers[telegramUser.id] = telegramUser
                            }
                            
                            let messageAndFile:(Message, TelegramMediaFile)? = apiMessages.compactMap { value in
                                return StoreMessage(apiMessage: value, accountPeerId: account.peerId, peerIsForum: peer.isForum)
                                }.compactMap { value in
                                    return locallyRenderedMessage(message: value, peers: peers)
                                }.sorted(by: {
                                    $0.id > $1.id
                                }).first(where: { value -> Bool in
                                    return value.media.first is TelegramMediaFile
                                }).map { ($0, $0.media.first as! TelegramMediaFile )}
                            
                            if let (message, media) = messageAndFile {
                                return Signal { subscriber in
                                    var dataDisposable: Disposable?
                                    var fetchDisposable: Disposable?
                                    var statusDisposable: Disposable?
                                    let removeDisposable = account.postbox.mediaBox.removeCachedResources([media.resource.id]).start(completed: {
                                        let reference = MediaResourceReference.media(media: .message(message: MessageReference(message), media: media), resource: media.resource)
                                        
                                        fetchDisposable = fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: .other, userContentType: .other, reference: reference).start()
                                        statusDisposable = account.postbox.mediaBox.resourceStatus(media.resource).start(next: { status in
                                            switch status {
                                            case let .Fetching(_, progress):
                                                if let size = media.size {
                                                    if progress == 0 {
                                                        subscriber.putNext(.started(Int(size)))
                                                    } else {
                                                        subscriber.putNext(.progress(Int(progress * Float(size)), Int(size)))
                                                    }
                                                }
                                            default:
                                                break
                                            }
                                        })
                                        
                                        dataDisposable = account.postbox.mediaBox.resourceData(media.resource, option: .complete(waitUntilFetchStatus: true)).start(next: { data in
                                            if data.complete {
                                                subscriber.putNext(.finished(data.path))
                                                subscriber.putCompletion()
                                            }
                                        })
                                    })
                                    
                                    
                                    
                                    return ActionDisposable {
                                        fetchDisposable?.dispose()
                                        dataDisposable?.dispose()
                                        statusDisposable?.dispose()
                                        removeDisposable.dispose()
                                    }
                                }
                            } else {
                                return .fail(.archiveLoad)
                            }
                        default:
                            break
                        }
                        return .fail(.archiveLoad)
                }
            } else {
                return .fail(.archiveLoad)
            }
    }
}

public func requestApplicationIcons(engine: TelegramEngine, source: String = "macos_app_icons") -> Signal<Void, NoError> {
    return engine.peers.resolvePeerByName(name: source, referrer: nil)
        |> mapToSignal { result -> Signal<Peer?, NoError> in
            switch result {
            case .progress:
                return .never()
            case let .result(peer):
                return .single(peer?._asPeer())
            }
        } |> mapToSignal { peer -> Signal<Void, NoError> in
            if let peer = peer, let inputPeer = apiInputPeer(peer) {
                return engine.account.network.request(Api.functions.messages.getHistory(peer: inputPeer, offsetId: 0, offsetDate: 0, addOffset: 0, limit: 100, maxId: Int32.max, minId: 0, hash: 0))
                |> retryRequest
                |> mapToSignal { result in
                    
                    switch result {
                    case let .channelMessages(_, _, _, _, apiMessages, _, apiChats, apiUsers):
                        var icons: [TelegramApplicationIcons.Icon] = []
                        for apiMessage in apiMessages.reversed() {
                            if let storeMessage = StoreMessage(apiMessage: apiMessage, accountPeerId: engine.account.peerId, peerIsForum: peer.isForum) {
                                var peers: [PeerId: Peer] = [:]
                                for chat in apiChats {
                                    if let groupOrChannel = parseTelegramGroupOrChannel(chat: chat) {
                                        peers[groupOrChannel.id] = groupOrChannel
                                    }
                                }
                                for user in apiUsers {
                                    let telegramUser = TelegramUser(user: user)
                                    peers[telegramUser.id] = telegramUser
                                }
                                
                                if let message = locallyRenderedMessage(message: storeMessage, peers: peers), let media = message.media.first as? TelegramMediaFile {
                                    icons.append(.init(file: media, reference: MessageReference(message)))
                                }
                            }
                        }
                        
                        return _internal_updateApplicationIcons(postbox: engine.account.postbox, icons: .init(icons: icons))
                    default:
                        break
                    }
                    return .complete()
                }
            } else {
                return .complete()
            }
        }
}


/*
 return Signal { subscriber in
     let fetchDispsable = fetchedMediaResource(mediaBox: engine.account.postbox.mediaBox, userLocation: .other, userContentType: .other, reference: MediaResourceReference.media(media: AnyMediaReference.message(message: MessageReference(message), media: media), resource: media.resource)).start()
     
     let dataDisposable = engine.account.postbox.mediaBox.resourceData(media.resource, option: .complete(waitUntilFetchStatus: true)).start(next: { data in
         if data.complete {
             if let data = try? Data(contentsOf: URL.init(fileURLWithPath: data.path)) {
                 subscriber.putNext(data)
                 subscriber.putCompletion()
             } else {
                 subscriber.putError(.xmlLoad)
             }
         }
     })
     return ActionDisposable {
         fetchDispsable.dispose()
         dataDisposable.dispose()
     }
 }
 */
