import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit
import Foundation

public final class TelegramKeyPair: Equatable {
    public let id: Int64
    public let publicKey: TelegramPublicKey
    
    public init(id: Int64, publicKey: TelegramPublicKey) {
        self.id = id
        self.publicKey = publicKey
    }
    
    public static func ==(lhs: TelegramKeyPair, rhs: TelegramKeyPair) -> Bool {
        if lhs.id != rhs.id {
            return false
        }
        if lhs.publicKey != rhs.publicKey {
            return false
        }
        return true
    }
}

public final class TelegramPublicKey: Equatable {
    let value: Int256
    
    init(value: Int256) {
        self.value = value
    }
    
    public static func ==(lhs: TelegramPublicKey, rhs: TelegramPublicKey) -> Bool {
        return lhs.value == rhs.value
    }
}
public extension TelegramPublicKey {
    convenience init?(data: Data) {
        guard data.count == 32 else {
            return nil
        }
        
        var int256 = Int256(
            _0: 0,
            _1: 0,
            _2: 0,
            _3: 0
        )
        
        data.withUnsafeBytes { buffer in
            if let baseAddress = buffer.baseAddress {
                let int64Buffer = baseAddress.assumingMemoryBound(to: Int64.self)
                int256._0 = int64Buffer[0]
                int256._1 = int64Buffer[1]
                int256._2 = int64Buffer[2]
                int256._3 = int64Buffer[3]
            }
        }
        
        self.init(value: int256)
        
        assert(self.data == data)
    }
    
    var data: Data {
        var data = Data(count: 32)
        data.withUnsafeMutableBytes { buffer in
            if let baseAddress = buffer.baseAddress {
                let int64Buffer = baseAddress.assumingMemoryBound(to: Int64.self)
                int64Buffer[0] = self.value._0
                int64Buffer[1] = self.value._1
                int64Buffer[2] = self.value._2
                int64Buffer[3] = self.value._3
            }
        }
        return data
    }
}

public protocol TelegramE2EEncryptionProvider: AnyObject {
    func generateKeyPair() -> TelegramKeyPair?
    func generateCallZeroBlock(keyPair: TelegramKeyPair, userId: Int64) -> Data?
}

public struct GroupCallInfo: Equatable {
    public var id: Int64
    public var accessHash: Int64
    public var participantCount: Int
    public var streamDcId: Int32?
    public var title: String?
    public var scheduleTimestamp: Int32?
    public var subscribedToScheduled: Bool
    public var recordingStartTimestamp: Int32?
    public var sortAscending: Bool
    public var defaultParticipantsAreMuted: GroupCallParticipantsContext.State.DefaultParticipantsAreMuted?
    public var isVideoEnabled: Bool
    public var unmutedVideoLimit: Int
    public var isStream: Bool
    public var isCreator: Bool
    
    public init(
        id: Int64,
        accessHash: Int64,
        participantCount: Int,
        streamDcId: Int32?,
        title: String?,
        scheduleTimestamp: Int32?,
        subscribedToScheduled: Bool,
        recordingStartTimestamp: Int32?,
        sortAscending: Bool,
        defaultParticipantsAreMuted: GroupCallParticipantsContext.State.DefaultParticipantsAreMuted?,
        isVideoEnabled: Bool,
        unmutedVideoLimit: Int,
        isStream: Bool,
        isCreator: Bool
    ) {
        self.id = id
        self.accessHash = accessHash
        self.participantCount = participantCount
        self.streamDcId = streamDcId
        self.title = title
        self.scheduleTimestamp = scheduleTimestamp
        self.subscribedToScheduled = subscribedToScheduled
        self.recordingStartTimestamp = recordingStartTimestamp
        self.sortAscending = sortAscending
        self.defaultParticipantsAreMuted = defaultParticipantsAreMuted
        self.isVideoEnabled = isVideoEnabled
        self.unmutedVideoLimit = unmutedVideoLimit
        self.isStream = isStream
        self.isCreator = isCreator
    }
}

public struct GroupCallSummary: Equatable {
    public var info: GroupCallInfo
    public var topParticipants: [GroupCallParticipantsContext.Participant]
}

extension GroupCallInfo {
    init?(_ call: Api.GroupCall) {
        switch call {
        case let .groupCall(flags, id, accessHash, participantsCount, title, streamDcId, recordStartDate, scheduleDate, _, unmutedVideoLimit, _, _):
            self.init(
                id: id,
                accessHash: accessHash,
                participantCount: Int(participantsCount),
                streamDcId: streamDcId,
                title: title,
                scheduleTimestamp: scheduleDate,
                subscribedToScheduled: (flags & (1 << 8)) != 0,
                recordingStartTimestamp: recordStartDate,
                sortAscending: (flags & (1 << 6)) != 0,
                defaultParticipantsAreMuted: GroupCallParticipantsContext.State.DefaultParticipantsAreMuted(isMuted: (flags & (1 << 1)) != 0, canChange: (flags & (1 << 2)) != 0),
                isVideoEnabled: (flags & (1 << 9)) != 0,
                unmutedVideoLimit: Int(unmutedVideoLimit),
                isStream: (flags & (1 << 12)) != 0,
                isCreator: (flags & (1 << 15)) != 0
            )
        case .groupCallDiscarded:
            return nil
        }
    }
}

public enum GetCurrentGroupCallError {
    case generic
}

public enum InternalGroupCallReference: Equatable {
    case id(id: Int64, accessHash: Int64)
    case link(slug: String)
    case message(id: MessageId)
}

extension InternalGroupCallReference {
    var apiInputGroupCall: Api.InputGroupCall {
        switch self {
        case let .id(id, accessHash):
            return .inputGroupCall(id: id, accessHash: accessHash)
        case let .link(slug):
            return .inputGroupCallSlug(slug: slug)
        case let .message(id):
            return .inputGroupCallInviteMessage(msgId: id.id)
        }
    }
}

func _internal_getCurrentGroupCall(account: Account, reference: InternalGroupCallReference, peerId: PeerId? = nil) -> Signal<GroupCallSummary?, GetCurrentGroupCallError> {
    let accountPeerId = account.peerId
    let inputCall: Api.InputGroupCall
    switch reference {
    case let .id(id, accessHash):
        inputCall = .inputGroupCall(id: id, accessHash: accessHash)
    case let .link(slug):
        inputCall = .inputGroupCallSlug(slug: slug)
    case let .message(id):
        if id.peerId.namespace != Namespaces.Peer.CloudUser {
            return .fail(.generic)
        }
        if id.namespace != Namespaces.Message.Cloud {
            return .fail(.generic)
        }
        inputCall = .inputGroupCallInviteMessage(msgId: id.id)
    }
    return account.network.request(Api.functions.phone.getGroupCall(call: inputCall, limit: 4))
    |> mapError { _ -> GetCurrentGroupCallError in
        return .generic
    }
    |> mapToSignal { result -> Signal<GroupCallSummary?, GetCurrentGroupCallError> in
        switch result {
        case let .groupCall(call, participants, _, chats, users):
            return account.postbox.transaction { transaction -> GroupCallSummary? in
                guard let info = GroupCallInfo(call) else {
                    return nil
                }
                
                let parsedPeers = AccumulatedPeers(transaction: transaction, chats: chats, users: users)
                if let peerId = peerId {
                    transaction.updatePeerCachedData(peerIds: [peerId], update: { _, current in
                        if let cachedData = current as? CachedChannelData {
                            return cachedData.withUpdatedActiveCall(CachedChannelData.ActiveCall.init(id: info.id, accessHash: info.accessHash, title: info.title, scheduleTimestamp: info.scheduleTimestamp, subscribedToScheduled: cachedData.activeCall?.subscribedToScheduled ?? false, isStream: info.isStream))
                        } else if let cachedData = current as? CachedGroupData {
                            return cachedData.withUpdatedActiveCall(CachedChannelData.ActiveCall(id: info.id, accessHash: info.accessHash, title: info.title, scheduleTimestamp: info.scheduleTimestamp, subscribedToScheduled: cachedData.activeCall?.subscribedToScheduled ?? false, isStream: info.isStream))
                        } else {
                            return current
                        }
                    })
                }
                
                updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: parsedPeers)
                
                let parsedParticipants = participants.compactMap { GroupCallParticipantsContext.Participant($0, transaction: transaction) }
                return GroupCallSummary(
                    info: info,
                    topParticipants: parsedParticipants
                )
            }
            |> mapError { _ -> GetCurrentGroupCallError in
            }
        }
    }
}

func _internal_getCurrentGroupCallInfo(account: Account, reference: InternalGroupCallReference) -> Signal<(participants: [PeerId], duration: Int32?)?, NoError> {
    let accountPeerId = account.peerId
    let inputCall: Api.InputGroupCall
    switch reference {
    case let .id(id, accessHash):
        inputCall = .inputGroupCall(id: id, accessHash: accessHash)
    case let .link(slug):
        inputCall = .inputGroupCallSlug(slug: slug)
    case let .message(id):
        if id.peerId.namespace != Namespaces.Peer.CloudUser {
            return .single(nil)
        }
        if id.namespace != Namespaces.Message.Cloud {
            return .single(nil)
        }
        inputCall = .inputGroupCallInviteMessage(msgId: id.id)
    }
    return account.network.request(Api.functions.phone.getGroupCall(call: inputCall, limit: 4))
    |> map(Optional.init)
    |> `catch` { _ -> Signal<Api.phone.GroupCall?, NoError> in
        return .single(nil)
    }
    |> mapToSignal { result -> Signal<(participants: [PeerId], duration: Int32?)?, NoError> in
        guard let result else {
            return .single(nil)
        }
        switch result {
        case let .groupCall(call, participants, _, chats, users):
            return account.postbox.transaction { transaction -> (participants: [PeerId], duration: Int32?)? in
                if case let .groupCallDiscarded(_, _, duration) = call {
                    return ([], duration)
                }
                
                let parsedPeers = AccumulatedPeers(transaction: transaction, chats: chats, users: users)
                
                updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: parsedPeers)
                
                let parsedParticipants = participants.compactMap { GroupCallParticipantsContext.Participant($0, transaction: transaction) }
                return (
                    parsedParticipants.compactMap(\.peer?.id),
                    nil
                )
            }
        }
    }
}

public enum CreateGroupCallError {
    case generic
    case anonymousNotAllowed
    case scheduledTooLate
}

func _internal_createGroupCall(account: Account, peerId: PeerId, title: String?, scheduleDate: Int32?, isExternalStream: Bool) -> Signal<GroupCallInfo, CreateGroupCallError> {
    return account.postbox.transaction { transaction -> Api.InputPeer? in
        let callPeer = transaction.getPeer(peerId).flatMap(apiInputPeer)
        return callPeer
    }
    |> castError(CreateGroupCallError.self)
    |> mapToSignal { inputPeer -> Signal<GroupCallInfo, CreateGroupCallError> in
        guard let inputPeer = inputPeer else {
            return .fail(.generic)
        }
        var flags: Int32 = 0
        if let _ = title {
            flags |= (1 << 0)
        }
        if let _ = scheduleDate {
            flags |= (1 << 1)
        }
        if isExternalStream {
            flags |= (1 << 2)
        }
        return account.network.request(Api.functions.phone.createGroupCall(flags: flags, peer: inputPeer, randomId: Int32.random(in: Int32.min ... Int32.max), title: title, scheduleDate: scheduleDate))
        |> mapError { error -> CreateGroupCallError in
            if error.errorDescription == "ANONYMOUS_CALLS_DISABLED" {
                return .anonymousNotAllowed
            } else if error.errorDescription == "SCHEDULE_DATE_TOO_LATE" {
                return .scheduledTooLate
            }
            return .generic
        }
        |> mapToSignal { result -> Signal<GroupCallInfo, CreateGroupCallError> in
            var parsedCall: GroupCallInfo?
            loop: for update in result.allUpdates {
                switch update {
                case let .updateGroupCall(_, _, call):
                    parsedCall = GroupCallInfo(call)
                    break loop
                default:
                    break
                }
            }
            
            guard let callInfo = parsedCall else {
                return .fail(.generic)
            }
            
            return account.postbox.transaction { transaction -> GroupCallInfo in
                transaction.updatePeerCachedData(peerIds: Set([peerId]), update: { _, cachedData -> CachedPeerData? in
                    if let cachedData = cachedData as? CachedChannelData {
                        return cachedData.withUpdatedActiveCall(CachedChannelData.ActiveCall(id: callInfo.id, accessHash: callInfo.accessHash, title: callInfo.title, scheduleTimestamp: callInfo.scheduleTimestamp, subscribedToScheduled: callInfo.subscribedToScheduled, isStream: callInfo.isStream))
                    } else if let cachedData = cachedData as? CachedGroupData {
                        return cachedData.withUpdatedActiveCall(CachedChannelData.ActiveCall(id: callInfo.id, accessHash: callInfo.accessHash, title: callInfo.title, scheduleTimestamp: callInfo.scheduleTimestamp, subscribedToScheduled: callInfo.subscribedToScheduled, isStream: callInfo.isStream))
                    } else {
                        return cachedData
                    }
                })
                
                account.stateManager.addUpdates(result)
                
                return callInfo
            }
            |> castError(CreateGroupCallError.self)
        }
    }
}

public enum StartScheduledGroupCallError {
    case generic
}

func _internal_startScheduledGroupCall(account: Account, peerId: PeerId, callId: Int64, accessHash: Int64) -> Signal<GroupCallInfo, StartScheduledGroupCallError> {
    return account.network.request(Api.functions.phone.startScheduledGroupCall(call: .inputGroupCall(id: callId, accessHash: accessHash)))
    |> mapError { error -> StartScheduledGroupCallError in
        return .generic
    }
    |> mapToSignal { result -> Signal<GroupCallInfo, StartScheduledGroupCallError> in
        var parsedCall: GroupCallInfo?
        loop: for update in result.allUpdates {
            switch update {
            case let .updateGroupCall(_, _, call):
                parsedCall = GroupCallInfo(call)
                break loop
            default:
                break
            }
        }
        
        guard let callInfo = parsedCall else {
            return .fail(.generic)
        }
        
        return account.postbox.transaction { transaction -> GroupCallInfo in
            transaction.updatePeerCachedData(peerIds: Set([peerId]), update: { _, cachedData -> CachedPeerData? in
                if let cachedData = cachedData as? CachedChannelData {
                    return cachedData.withUpdatedActiveCall(CachedChannelData.ActiveCall(id: callInfo.id, accessHash: callInfo.accessHash, title: callInfo.title, scheduleTimestamp: nil, subscribedToScheduled: false, isStream: callInfo.isStream))
                } else if let cachedData = cachedData as? CachedGroupData {
                    return cachedData.withUpdatedActiveCall(CachedChannelData.ActiveCall(id: callInfo.id, accessHash: callInfo.accessHash, title: callInfo.title, scheduleTimestamp: nil, subscribedToScheduled: false, isStream: callInfo.isStream))
                } else {
                    return cachedData
                }
            })
            
            account.stateManager.addUpdates(result)
            
            return callInfo
        }
        |> castError(StartScheduledGroupCallError.self)
    }
}

public enum ToggleScheduledGroupCallSubscriptionError {
    case generic
}

func _internal_toggleScheduledGroupCallSubscription(account: Account, peerId: PeerId, reference: InternalGroupCallReference, subscribe: Bool) -> Signal<Void, ToggleScheduledGroupCallSubscriptionError> {
    return account.postbox.transaction { transaction -> Void in
        transaction.updatePeerCachedData(peerIds: Set([peerId]), update: { _, cachedData -> CachedPeerData? in
            if let cachedData = cachedData as? CachedChannelData, let activeCall = cachedData.activeCall {
                return cachedData.withUpdatedActiveCall(CachedChannelData.ActiveCall(id: activeCall.id, accessHash: activeCall.accessHash, title: activeCall.title, scheduleTimestamp: activeCall.scheduleTimestamp, subscribedToScheduled: true, isStream: activeCall.isStream))
            } else if let cachedData = cachedData as? CachedGroupData, let activeCall = cachedData.activeCall {
                return cachedData.withUpdatedActiveCall(CachedChannelData.ActiveCall(id: activeCall.id, accessHash: activeCall.accessHash, title: activeCall.title, scheduleTimestamp: activeCall.scheduleTimestamp, subscribedToScheduled: true, isStream: activeCall.isStream))
            } else {
                return cachedData
            }
        })
    }
    |> castError(ToggleScheduledGroupCallSubscriptionError.self)
    |> mapToSignal { _ -> Signal<Void, ToggleScheduledGroupCallSubscriptionError> in
        return account.network.request(Api.functions.phone.toggleGroupCallStartSubscription(call: reference.apiInputGroupCall, subscribed: subscribe ? .boolTrue : .boolFalse))
        |> mapError { error -> ToggleScheduledGroupCallSubscriptionError in
            return .generic
        }
        |> mapToSignal { result -> Signal<Void, ToggleScheduledGroupCallSubscriptionError> in
            var parsedCall: GroupCallInfo?
            loop: for update in result.allUpdates {
                switch update {
                case let .updateGroupCall(_, _, call):
                    parsedCall = GroupCallInfo(call)
                    break loop
                default:
                    break
                }
            }
            
            guard let callInfo = parsedCall else {
                return .fail(.generic)
            }
            
            return account.postbox.transaction { transaction in
                transaction.updatePeerCachedData(peerIds: Set([peerId]), update: { _, cachedData -> CachedPeerData? in
                    if let cachedData = cachedData as? CachedChannelData {
                        return cachedData.withUpdatedActiveCall(CachedChannelData.ActiveCall(id: callInfo.id, accessHash: callInfo.accessHash, title: callInfo.title, scheduleTimestamp: callInfo.scheduleTimestamp, subscribedToScheduled: callInfo.subscribedToScheduled, isStream: callInfo.isStream))
                    } else if let cachedData = cachedData as? CachedGroupData {
                        return cachedData.withUpdatedActiveCall(CachedChannelData.ActiveCall(id: callInfo.id, accessHash: callInfo.accessHash, title: callInfo.title, scheduleTimestamp: callInfo.scheduleTimestamp, subscribedToScheduled: callInfo.subscribedToScheduled, isStream: callInfo.isStream))
                    } else {
                        return cachedData
                    }
                })
                
                account.stateManager.addUpdates(result)
            }
            |> castError(ToggleScheduledGroupCallSubscriptionError.self)
        }
    }
}

public enum UpdateGroupCallJoinAsPeerError {
    case generic
}

func _internal_updateGroupCallJoinAsPeer(account: Account, peerId: PeerId, joinAs: PeerId) -> Signal<Never, UpdateGroupCallJoinAsPeerError> {
    return account.postbox.transaction { transaction -> (Api.InputPeer, Api.InputPeer)? in
        if let peer = transaction.getPeer(peerId), let joinAsPeer = transaction.getPeer(joinAs), let inputPeer = apiInputPeer(peer), let joinInputPeer = apiInputPeer(joinAsPeer) {
            return (inputPeer, joinInputPeer)
        } else {
            return nil
        }
    }
    |> castError(UpdateGroupCallJoinAsPeerError.self)
    |> mapToSignal { result in
        guard let (inputPeer, joinInputPeer) = result else {
            return .fail(.generic)
        }
        return account.network.request(Api.functions.phone.saveDefaultGroupCallJoinAs(peer: inputPeer, joinAs: joinInputPeer))
        |> mapError { _ -> UpdateGroupCallJoinAsPeerError in
            return .generic
        }
        |> mapToSignal { result -> Signal<Never, UpdateGroupCallJoinAsPeerError> in
            return account.postbox.transaction { transaction in
                transaction.updatePeerCachedData(peerIds: Set([peerId]), update: { _, cachedData -> CachedPeerData? in
                    if let cachedData = cachedData as? CachedChannelData {
                        return cachedData.withUpdatedCallJoinPeerId(joinAs)
                    } else if let cachedData = cachedData as? CachedGroupData {
                        return cachedData.withUpdatedCallJoinPeerId(joinAs)
                    } else {
                        return cachedData
                    }
                })
            }
            |> castError(UpdateGroupCallJoinAsPeerError.self)
            |> ignoreValues
        }
    }
}

public enum GetGroupCallParticipantsError {
    case generic
}

func _internal_getGroupCallParticipants(account: Account, reference: InternalGroupCallReference, offset: String, ssrcs: [UInt32], limit: Int32, sortAscending: Bool?) -> Signal<GroupCallParticipantsContext.State, GetGroupCallParticipantsError> {
    let accountPeerId = account.peerId
    
    let sortAscendingValue: Signal<(Bool, Int32?, Bool, GroupCallParticipantsContext.State.DefaultParticipantsAreMuted?, Bool, Int, Bool, Bool), GetGroupCallParticipantsError>
    
    sortAscendingValue = _internal_getCurrentGroupCall(account: account, reference: reference)
    |> mapError { _ -> GetGroupCallParticipantsError in
        return .generic
    }
    |> mapToSignal { result -> Signal<(Bool, Int32?, Bool, GroupCallParticipantsContext.State.DefaultParticipantsAreMuted?, Bool, Int, Bool, Bool), GetGroupCallParticipantsError> in
        guard let result = result else {
            return .fail(.generic)
        }
        return .single((sortAscending ?? result.info.sortAscending, result.info.scheduleTimestamp, result.info.subscribedToScheduled, result.info.defaultParticipantsAreMuted, result.info.isVideoEnabled, result.info.unmutedVideoLimit, result.info.isStream, result.info.isCreator))
    }

    return combineLatest(
        account.network.request(Api.functions.phone.getGroupParticipants(call: reference.apiInputGroupCall, ids: [], sources: ssrcs.map { Int32(bitPattern: $0) }, offset: offset, limit: limit))
        |> mapError { _ -> GetGroupCallParticipantsError in
            return .generic
        },
        sortAscendingValue
    )
    |> mapToSignal { result, sortAscendingAndScheduleTimestamp -> Signal<GroupCallParticipantsContext.State, GetGroupCallParticipantsError> in
        return account.postbox.transaction { transaction -> GroupCallParticipantsContext.State in
            var parsedParticipants: [GroupCallParticipantsContext.Participant] = []
            let totalCount: Int
            let version: Int32
            let nextParticipantsFetchOffset: String?
            
            let (sortAscendingValue, scheduleTimestamp, subscribedToScheduled, defaultParticipantsAreMuted, isVideoEnabled, unmutedVideoLimit, isStream, isCreator) = sortAscendingAndScheduleTimestamp
            
            switch result {
            case let .groupParticipants(count, participants, nextOffset, chats, users, apiVersion):
                totalCount = Int(count)
                version = apiVersion
                
                if participants.count != 0 && !nextOffset.isEmpty {
                    nextParticipantsFetchOffset = nextOffset
                } else {
                    nextParticipantsFetchOffset = nil
                }
                
                let parsedPeers = AccumulatedPeers(transaction: transaction, chats: chats, users: users)
                updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: parsedPeers)
                
                parsedParticipants = participants.compactMap { GroupCallParticipantsContext.Participant($0, transaction: transaction) }
            }

            parsedParticipants.sort(by: { GroupCallParticipantsContext.Participant.compare(lhs: $0, rhs: $1, sortAscending: sortAscendingValue) })
            
            return GroupCallParticipantsContext.State(
                participants: parsedParticipants,
                nextParticipantsFetchOffset: nextParticipantsFetchOffset,
                adminIds: Set(),
                isCreator: isCreator,
                defaultParticipantsAreMuted: defaultParticipantsAreMuted ?? GroupCallParticipantsContext.State.DefaultParticipantsAreMuted(isMuted: false, canChange: false),
                sortAscending: sortAscendingValue,
                recordingStartTimestamp: nil,
                title: nil,
                scheduleTimestamp: scheduleTimestamp,
                subscribedToScheduled: subscribedToScheduled,
                totalCount: totalCount,
                isVideoEnabled: isVideoEnabled,
                unmutedVideoLimit: unmutedVideoLimit,
                isStream: isStream,
                version: version
            )
        }
        |> castError(GetGroupCallParticipantsError.self)
    }
}

public enum JoinGroupCallError {
    case generic
    case anonymousNotAllowed
    case tooManyParticipants
    case invalidJoinAsPeer
}

public struct JoinGroupCallResult {
    public enum ConnectionMode {
        case rtc
        case broadcast(isExternalStream: Bool)
    }

    public struct E2EState {
        public let subChain0: (offset: Int, blocks: [Data])
        public let subChain1: (offset: Int, blocks: [Data])

        public init(subChain0: (offset: Int, blocks: [Data]), subChain1: (offset: Int, blocks: [Data])) {
            self.subChain0 = subChain0
            self.subChain1 = subChain1
        }
    }
    
    public var callInfo: GroupCallInfo
    public var state: GroupCallParticipantsContext.State
    public var connectionMode: ConnectionMode
    public var jsonParams: String
    public var e2eState: E2EState?
}

public class JoinGroupCallE2E {
    public let publicKey: TelegramPublicKey
    public let block: Data
    
    public init(publicKey: TelegramPublicKey, block: Data) {
        self.publicKey = publicKey
        self.block = block
    }
}

func _internal_joinGroupCall(account: Account, peerId: PeerId?, joinAs: PeerId?, callId: Int64, reference: InternalGroupCallReference, preferMuted: Bool, joinPayload: String, peerAdminIds: Signal<[PeerId], NoError>, inviteHash: String? = nil, generateE2E: ((Data?) -> JoinGroupCallE2E?)?) -> Signal<JoinGroupCallResult, JoinGroupCallError> {
    enum InternalJoinError {
        case error(JoinGroupCallError)
        case restart
    }
    
    var e2eData: Signal<JoinGroupCallE2E?, NoError> = .single(nil)
    if let generateE2E {
        e2eData = _internal_pollConferenceCallBlockchain(network: account.network, reference: reference, subChainId: 0, offset: -1, limit: 1)
        |> map { result -> JoinGroupCallE2E? in
            guard let result else {
                return nil
            }
            guard let block = result.blocks.last else {
                return generateE2E(nil)
            }
            return generateE2E(block)
        }
    }
    
    let signal: Signal<JoinGroupCallResult, InternalJoinError> = e2eData
    |> castError(InternalJoinError.self)
    |> mapToSignal { e2eData -> Signal<JoinGroupCallResult, InternalJoinError> in
        return account.postbox.transaction { transaction -> Api.InputPeer? in
            if let joinAs = joinAs {
                return transaction.getPeer(joinAs).flatMap(apiInputPeer)
            } else {
                return .inputPeerSelf
            }
        }
        |> castError(InternalJoinError.self)
        |> mapToSignal { inputJoinAs -> Signal<JoinGroupCallResult, InternalJoinError> in
            guard let inputJoinAs = inputJoinAs else {
                return .fail(.error(.generic))
            }
            
            var flags: Int32 = 0
            if preferMuted {
                flags |= (1 << 0)
            }
            flags |= (1 << 2)
            if let _ = inviteHash {
                flags |= (1 << 1)
            }
            if e2eData != nil {
                flags |= (1 << 3)
            }
            
            let joinRequest = account.network.request(Api.functions.phone.joinGroupCall(flags: flags, call: reference.apiInputGroupCall, joinAs: inputJoinAs, inviteHash: inviteHash, publicKey: e2eData?.publicKey.value, block: (e2eData?.block).flatMap({ Buffer.init(data: $0) }), params: .dataJSON(data: joinPayload)))
            |> `catch` { error -> Signal<Api.Updates, InternalJoinError> in
                if error.errorDescription == "GROUPCALL_ANONYMOUS_FORBIDDEN" {
                    return .fail(.error(.anonymousNotAllowed))
                } else if error.errorDescription == "GROUPCALL_PARTICIPANTS_TOO_MUCH" {
                    return .fail(.error(.tooManyParticipants))
                } else if error.errorDescription == "JOIN_AS_PEER_INVALID" {
                    if let peerId {
                        let _ = (account.postbox.transaction { transaction -> Void in
                            transaction.updatePeerCachedData(peerIds: Set([peerId]), update: { _, current in
                                if let current = current as? CachedChannelData {
                                    return current.withUpdatedCallJoinPeerId(nil)
                                } else if let current = current as? CachedGroupData {
                                    return current.withUpdatedCallJoinPeerId(nil)
                                } else {
                                    return current
                                }
                            })
                        }).start()
                    }
                    
                    return .fail(.error(.invalidJoinAsPeer))
                } else if error.errorDescription == "GROUPCALL_INVALID" {
                    return account.postbox.transaction { transaction -> Signal<Api.Updates, InternalJoinError> in
                        if let peerId {
                            transaction.updatePeerCachedData(peerIds: Set([peerId]), update: { _, current in
                                if let current = current as? CachedGroupData {
                                    if current.activeCall?.id == callId {
                                        return current.withUpdatedActiveCall(nil)
                                    }
                                } else if let current = current as? CachedChannelData {
                                    if current.activeCall?.id == callId {
                                        return current.withUpdatedActiveCall(nil)
                                    }
                                }
                                return current
                            })
                        }
                        
                        return .fail(.error(.generic))
                    }
                    |> castError(InternalJoinError.self)
                    |> switchToLatest
                } else if error.errorDescription.hasPrefix("CONF_WRITE_CHAIN_INVALID") {
                    return .fail(.restart)
                } else {
                    return .fail(.error(.generic))
                }
            }
            
            let getParticipantsRequest = _internal_getGroupCallParticipants(account: account, reference: reference, offset: "", ssrcs: [], limit: 100, sortAscending: true)
            |> mapError { _ -> InternalJoinError in
                return .error(.generic)
            }
            
            return combineLatest(
                joinRequest,
                getParticipantsRequest
            )
            |> mapToSignal { updates, participantsState -> Signal<JoinGroupCallResult, InternalJoinError> in
                let peer = account.postbox.transaction { transaction -> Peer? in
                    return peerId.flatMap(transaction.getPeer)
                }
                |> castError(InternalJoinError.self)
                
                return combineLatest(
                    peerAdminIds |> castError(InternalJoinError.self) |> take(1),
                    peer
                )
                |> mapToSignal { peerAdminIds, peer -> Signal<JoinGroupCallResult, InternalJoinError> in
                    var state = participantsState
                    if let peer {
                        if let channel = peer as? TelegramChannel {
                            state.isCreator = channel.flags.contains(.isCreator)
                        } else if let group = peer as? TelegramGroup {
                            if case .creator = group.role {
                                state.isCreator = true
                            } else {
                                state.isCreator = false
                            }
                        }
                    }
                    
                    account.stateManager.addUpdates(updates)
                    
                    var maybeParsedCall: GroupCallInfo?
                    var maybeParsedClientParams: String?
                    loop: for update in updates.allUpdates {
                        switch update {
                        case let .updateGroupCall(_, _, call):
                            maybeParsedCall = GroupCallInfo(call)
                            
                            switch call {
                            case let .groupCall(flags, _, _, _, title, _, recordStartDate, scheduleDate, _, unmutedVideoLimit, _, _):
                                let isMuted = (flags & (1 << 1)) != 0
                                let canChange = (flags & (1 << 2)) != 0
                                let isVideoEnabled = (flags & (1 << 9)) != 0
                                state.defaultParticipantsAreMuted = GroupCallParticipantsContext.State.DefaultParticipantsAreMuted(isMuted: isMuted, canChange: canChange)
                                state.title = title
                                state.recordingStartTimestamp = recordStartDate
                                state.scheduleTimestamp = scheduleDate
                                state.isVideoEnabled = isVideoEnabled
                                state.unmutedVideoLimit = Int(unmutedVideoLimit)
                            default:
                                break
                            }
                        case let .updateGroupCallConnection(_, params):
                            switch params {
                            case let .dataJSON(data):
                                maybeParsedClientParams = data
                            }
                        default:
                            break
                        }
                    }
                    
                    guard let parsedCall = maybeParsedCall, let parsedClientParams = maybeParsedClientParams else {
                        return .fail(.error(.generic))
                    }
                    
                    state.sortAscending = parsedCall.sortAscending
                    
                    state.adminIds = Set(peerAdminIds)
                    
                    let connectionMode: JoinGroupCallResult.ConnectionMode
                    if let clientParamsData = parsedClientParams.data(using: .utf8), let dict = (try? JSONSerialization.jsonObject(with: clientParamsData, options: [])) as? [String: Any] {
                        if let stream = dict["stream"] as? Bool, stream {
                            var isExternalStream = false
                            if let rtmp = dict["rtmp"] as? Bool, rtmp {
                                isExternalStream = true
                            }
                            connectionMode = .broadcast(isExternalStream: isExternalStream)
                        } else {
                            connectionMode = .rtc
                        }
                    } else {
                        connectionMode = .broadcast(isExternalStream: false)
                    }
                    
                    return account.postbox.transaction { transaction -> Signal<JoinGroupCallResult, InternalJoinError> in
                        if let peerId {
                            transaction.updatePeerCachedData(peerIds: Set([peerId]), update: { _, cachedData -> CachedPeerData? in
                                if let cachedData = cachedData as? CachedChannelData {
                                    return cachedData.withUpdatedCallJoinPeerId(joinAs).withUpdatedActiveCall(CachedChannelData.ActiveCall(id: parsedCall.id, accessHash: parsedCall.accessHash, title: parsedCall.title, scheduleTimestamp: nil, subscribedToScheduled: false, isStream: parsedCall.isStream))
                                } else if let cachedData = cachedData as? CachedGroupData {
                                    return cachedData.withUpdatedCallJoinPeerId(joinAs).withUpdatedActiveCall(CachedChannelData.ActiveCall(id: parsedCall.id, accessHash: parsedCall.accessHash, title: parsedCall.title, scheduleTimestamp: nil, subscribedToScheduled: false, isStream: parsedCall.isStream))
                                } else {
                                    return cachedData
                                }
                            })
                        }
                        
                        var state = state
                        
                        var e2eSubChain1State: (offset: Int, blocks: [Data])?
                        var e2eSubChain0State: (offset: Int, blocks: [Data])?
                        
                        for update in updates.allUpdates {
                            switch update {
                            case let .updateGroupCallParticipants(_, participants, _):
                                loop: for participant in participants {
                                    switch participant {
                                    case let .groupCallParticipant(flags, apiPeerId, date, activeDate, source, volume, about, raiseHandRating, video, presentation):
                                        let peerId: PeerId = apiPeerId.peerId
                                        let ssrc = UInt32(bitPattern: source)
                                        guard let peer = transaction.getPeer(peerId) else {
                                            continue loop
                                        }
                                        let muted = (flags & (1 << 0)) != 0
                                        let mutedByYou = (flags & (1 << 9)) != 0
                                        var muteState: GroupCallParticipantsContext.Participant.MuteState?
                                        if muted {
                                            let canUnmute = (flags & (1 << 2)) != 0
                                            muteState = GroupCallParticipantsContext.Participant.MuteState(canUnmute: canUnmute, mutedByYou: mutedByYou)
                                        } else if mutedByYou {
                                            muteState = GroupCallParticipantsContext.Participant.MuteState(canUnmute: false, mutedByYou: mutedByYou)
                                        }
                                        var videoDescription = video.flatMap(GroupCallParticipantsContext.Participant.VideoDescription.init)
                                        var presentationDescription = presentation.flatMap(GroupCallParticipantsContext.Participant.VideoDescription.init)
                                        if muteState?.canUnmute == false {
                                            videoDescription = nil
                                            presentationDescription = nil
                                        }
                                        let joinedVideo = (flags & (1 << 15)) != 0
                                        if !state.participants.contains(where: { $0.id == .peer(peer.id) }) {
                                            state.participants.append(GroupCallParticipantsContext.Participant(
                                                id: .peer(peer.id),
                                                peer: EnginePeer(peer),
                                                ssrc: ssrc,
                                                videoDescription: videoDescription,
                                                presentationDescription: presentationDescription,
                                                joinTimestamp: date,
                                                raiseHandRating: raiseHandRating,
                                                hasRaiseHand: raiseHandRating != nil,
                                                activityTimestamp: activeDate.flatMap(Double.init),
                                                activityRank: nil,
                                                muteState: muteState,
                                                volume: volume,
                                                about: about,
                                                joinedVideo: joinedVideo
                                            ))
                                        }
                                    }
                                }
                            case let .updateGroupCallChainBlocks(_, subChainId, blocks, nextOffset):
                                if subChainId == 0 {
                                    e2eSubChain0State = (offset: Int(nextOffset), blocks: blocks.map { $0.makeData() })
                                } else {
                                    e2eSubChain1State = (offset: Int(nextOffset), blocks: blocks.map { $0.makeData() })
                                }
                            default:
                                break
                            }
                        }

                        var e2eState: JoinGroupCallResult.E2EState?
                        if let e2eSubChain0State, let e2eSubChain1State {
                            e2eState = JoinGroupCallResult.E2EState(
                                subChain0: e2eSubChain0State,
                                subChain1: e2eSubChain1State
                            )
                        }

                        if generateE2E != nil && e2eState == nil {
                            return .fail(.error(.generic))
                        }
                        
                        state.participants.sort(by: { GroupCallParticipantsContext.Participant.compare(lhs: $0, rhs: $1, sortAscending: state.sortAscending) })
                        
                        return .single(JoinGroupCallResult(
                            callInfo: parsedCall,
                            state: state,
                            connectionMode: connectionMode,
                            jsonParams: parsedClientParams,
                            e2eState: e2eState
                        ))
                    }
                    |> castError(InternalJoinError.self)
                    |> switchToLatest
                }
            }
        }
    }
    
    return signal |> restartOrMapError { error in
        switch error {
        case .restart:
            return .restart
        case let .error(e):
            return .error(e)
        }
    }
}

public enum InviteConferenceCallParticipantError {
    case generic
    case privacy(peer: EnginePeer?)
}

func _internal_inviteConferenceCallParticipant(account: Account, reference: InternalGroupCallReference, peerId: EnginePeer.Id, isVideo: Bool) -> Signal<MessageId, InviteConferenceCallParticipantError> {
    return account.postbox.transaction { transaction -> Api.InputUser? in
        return transaction.getPeer(peerId).flatMap(apiInputUser)
    }
    |> castError(InviteConferenceCallParticipantError.self)
    |> mapToSignal { inputPeer -> Signal<MessageId, InviteConferenceCallParticipantError> in
        guard let inputPeer else {
            return .fail(.generic)
        }
        
        var flags: Int32 = 0
        if isVideo {
            flags |= 1 << 0
        }
        return account.network.request(Api.functions.phone.inviteConferenceCallParticipant(flags: flags, call: reference.apiInputGroupCall, userId: inputPeer))
        |> map(Optional.init)
        |> `catch` { error -> Signal<Api.Updates?, InviteConferenceCallParticipantError> in
            if error.errorDescription == "USER_PRIVACY_RESTRICTED" {
                return account.postbox.transaction { transaction -> InviteConferenceCallParticipantError in
                    return .privacy(peer: transaction.getPeer(peerId).flatMap(EnginePeer.init))
                }
                |> castError(InviteConferenceCallParticipantError.self)
                |> mapToSignal { error -> Signal<Api.Updates?, InviteConferenceCallParticipantError> in
                    return .fail(error)
                }
            }
            return .fail(.generic)
        }
        |> mapToSignal { result -> Signal<MessageId, InviteConferenceCallParticipantError> in
            if let result {
                account.stateManager.addUpdates(result)
                if let message = result.messageIds.first {
                    return .single(message)
                }
            }
            return .fail(.generic)
        }
    }
}

public enum RemoveGroupCallBlockchainParticipantsMode {
    case kick
    case cleanup
}

public enum RemoveGroupCallBlockchainParticipantsResult {
    case success
    case pollBlocksAndRetry
}

func _internal_removeGroupCallBlockchainParticipants(account: Account, callId: Int64, accessHash: Int64, mode: RemoveGroupCallBlockchainParticipantsMode, participantIds: [Int64], block: Data) -> Signal<RemoveGroupCallBlockchainParticipantsResult, NoError> {
    var flags: Int32 = 0
    switch mode {
    case .kick:
        flags |= 1 << 1
    case .cleanup:
        flags |= 1 << 0
    }
    return account.network.request(Api.functions.phone.deleteConferenceCallParticipants(flags: flags, call: .inputGroupCall(id: callId, accessHash: accessHash), ids: participantIds, block: Buffer(data: block)))
    |> map { updates -> RemoveGroupCallBlockchainParticipantsResult in
        account.stateManager.addUpdates(updates)
        return .success
    }
    |> `catch` { _ -> Signal<RemoveGroupCallBlockchainParticipantsResult, NoError> in
        return .single(.pollBlocksAndRetry)
    }
}

public struct JoinGroupCallAsScreencastResult {
    public var jsonParams: String
    public var endpointId: String
}

func _internal_joinGroupCallAsScreencast(account: Account, callId: Int64, accessHash: Int64, joinPayload: String) -> Signal<JoinGroupCallAsScreencastResult, JoinGroupCallError> {
    return account.network.request(Api.functions.phone.joinGroupCallPresentation(call: .inputGroupCall(id: callId, accessHash: accessHash), params: .dataJSON(data: joinPayload)))
    |> mapError { _ -> JoinGroupCallError in
        return .generic
    }
    |> mapToSignal { updates -> Signal<JoinGroupCallAsScreencastResult, JoinGroupCallError> in
        account.stateManager.addUpdates(updates)

        var maybeParsedClientParams: String?
        loop: for update in updates.allUpdates {
            switch update {
            case let .updateGroupCallConnection(_, params):
                switch params {
                case let .dataJSON(data):
                    maybeParsedClientParams = data
                }
            default:
                break
            }
        }

        guard let parsedClientParams = maybeParsedClientParams else {
            return .fail(.generic)
        }

        var maybeEndpointId: String?

        if let jsonData = parsedClientParams.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
            if let videoSection = json["video"] as? [String: Any] {
                maybeEndpointId = videoSection["endpoint"] as? String
            }
        }

        guard let endpointId = maybeEndpointId else {
            return .fail(.generic)
        }

        return .single(JoinGroupCallAsScreencastResult(
            jsonParams: parsedClientParams,
            endpointId: endpointId
        ))
    }
}

public enum LeaveGroupCallAsScreencastError {
    case generic
}

func _internal_leaveGroupCallAsScreencast(account: Account, callId: Int64, accessHash: Int64) -> Signal<Never, LeaveGroupCallAsScreencastError> {
    return account.network.request(Api.functions.phone.leaveGroupCallPresentation(call: .inputGroupCall(id: callId, accessHash: accessHash)))
    |> mapError { _ -> LeaveGroupCallAsScreencastError in
        return .generic
    }
    |> mapToSignal { updates -> Signal<Never, LeaveGroupCallAsScreencastError> in
        account.stateManager.addUpdates(updates)

        return .complete()
    }
}

public enum LeaveGroupCallError {
    case generic
}

func _internal_leaveGroupCall(account: Account, callId: Int64, accessHash: Int64, source: UInt32) -> Signal<Never, LeaveGroupCallError> {
    return account.network.request(Api.functions.phone.leaveGroupCall(call: .inputGroupCall(id: callId, accessHash: accessHash), source: Int32(bitPattern: source)))
    |> mapError { _ -> LeaveGroupCallError in
        return .generic
    }
    |> mapToSignal { result -> Signal<Never, LeaveGroupCallError> in
        account.stateManager.addUpdates(result)
        
        return .complete()
    }
}

public enum StopGroupCallError {
    case generic
}

func _internal_stopGroupCall(account: Account, peerId: PeerId?, callId: Int64, accessHash: Int64) -> Signal<Never, StopGroupCallError> {
    return account.network.request(Api.functions.phone.discardGroupCall(call: .inputGroupCall(id: callId, accessHash: accessHash)))
    |> mapError { _ -> StopGroupCallError in
        return .generic
    }
    |> mapToSignal { result -> Signal<Never, StopGroupCallError> in
        return account.postbox.transaction { transaction -> Void in
            if let peerId {
                transaction.updatePeerCachedData(peerIds: Set([peerId]), update: { _, cachedData -> CachedPeerData? in
                    if let cachedData = cachedData as? CachedChannelData {
                        return cachedData.withUpdatedActiveCall(nil).withUpdatedCallJoinPeerId(nil)
                    } else if let cachedData = cachedData as? CachedGroupData {
                        return cachedData.withUpdatedActiveCall(nil).withUpdatedCallJoinPeerId(nil)
                    } else {
                        return cachedData
                    }
                })
                if var peer = transaction.getPeer(peerId) as? TelegramChannel {
                    var flags = peer.flags
                    flags.remove(.hasVoiceChat)
                    flags.remove(.hasActiveVoiceChat)
                    peer = peer.withUpdatedFlags(flags)
                    updatePeersCustom(transaction: transaction, peers: [peer], update: { _, updated in
                        return updated
                    })
                }
                if var peer = transaction.getPeer(peerId) as? TelegramGroup {
                    var flags = peer.flags
                    flags.remove(.hasVoiceChat)
                    flags.remove(.hasActiveVoiceChat)
                    peer = peer.updateFlags(flags: flags, version: peer.version)
                    updatePeersCustom(transaction: transaction, peers: [peer], update: { _, updated in
                        return updated
                    })
                }
            }
            
            account.stateManager.addUpdates(result)
        }
        |> castError(StopGroupCallError.self)
        |> ignoreValues
    }
}

func _internal_checkGroupCall(account: Account, callId: Int64, accessHash: Int64, ssrcs: [UInt32]) -> Signal<[UInt32], NoError> {
    return account.network.request(Api.functions.phone.checkGroupCall(call: .inputGroupCall(id: callId, accessHash: accessHash), sources: ssrcs.map(Int32.init(bitPattern:))))
    |> `catch` { _ -> Signal<[Int32], NoError> in
        return .single([])
    }
    |> map { result -> [UInt32] in
        return result.map(UInt32.init(bitPattern:))
    }
}

private func binaryInsertionIndex(_ inputArr: [GroupCallParticipantsContext.Participant], searchItem: Int32) -> Int {
    var lo = 0
    var hi = inputArr.count - 1
    while lo <= hi {
        let mid = (lo + hi) / 2
        if inputArr[mid].joinTimestamp < searchItem {
            lo = mid + 1
        } else if searchItem < inputArr[mid].joinTimestamp {
            hi = mid - 1
        } else {
            return mid
        }
    }
    return lo
}

public final class GroupCallParticipantsContext {
    public struct Participant: Equatable, CustomStringConvertible {
        public struct MuteState: Equatable {
            public var canUnmute: Bool
            public var mutedByYou: Bool
            
            public init(canUnmute: Bool, mutedByYou: Bool) {
                self.canUnmute = canUnmute
                self.mutedByYou = mutedByYou
            }
        }

        public struct VideoDescription: Equatable {
            public struct SsrcGroup: Equatable {
                public var semantics: String
                public var ssrcs: [UInt32]
            }

            public var endpointId: String
            public var ssrcGroups: [SsrcGroup]
            public var audioSsrc: UInt32?
            public var isPaused: Bool
            
            public init(endpointId: String, ssrcGroups: [SsrcGroup], audioSsrc: UInt32?, isPaused: Bool) {
                self.endpointId = endpointId
                self.ssrcGroups = ssrcGroups
                self.audioSsrc = audioSsrc
                self.isPaused = isPaused
            }
        }
        
        public enum Id: Hashable, Comparable, CustomStringConvertible {
            case peer(EnginePeer.Id)
            case blockchain(String)
            
            public var description: String { 
                switch self {
                case let .peer(id):
                    return "\(id)"
                case let .blockchain(internalId):
                    return internalId
                }
            }

            public static func <(lhs: Id, rhs: Id) -> Bool {
                switch lhs {
                case let .peer(lhsId):
                    switch rhs {
                    case let .peer(rhsId):
                        return lhsId < rhsId
                    case .blockchain:
                        return true
                    }
                case let .blockchain(lhsData):
                    switch rhs {
                    case .peer:
                        return false
                    case let .blockchain(rhsData):
                        return lhsData < rhsData
                    }
                }
            }
        }
        
        public var id: Id
        public var peer: EnginePeer?
        public var ssrc: UInt32?
        public var videoDescription: VideoDescription?
        public var presentationDescription: VideoDescription?
        public var joinTimestamp: Int32
        public var raiseHandRating: Int64?
        public var hasRaiseHand: Bool
        public var activityTimestamp: Double?
        public var activityRank: Int?
        public var muteState: MuteState?
        public var volume: Int32?
        public var about: String?
        public var joinedVideo: Bool
        
        public init(
            id: Id,
            peer: EnginePeer?,
            ssrc: UInt32?,
            videoDescription: VideoDescription?,
            presentationDescription: VideoDescription?,
            joinTimestamp: Int32,
            raiseHandRating: Int64?,
            hasRaiseHand: Bool,
            activityTimestamp: Double?,
            activityRank: Int?,
            muteState: MuteState?,
            volume: Int32?,
            about: String?,
            joinedVideo: Bool
        ) {
            self.id = id
            self.peer = peer
            self.ssrc = ssrc
            self.videoDescription = videoDescription
            self.presentationDescription = presentationDescription
            self.joinTimestamp = joinTimestamp
            self.raiseHandRating = raiseHandRating
            self.hasRaiseHand = hasRaiseHand
            self.activityTimestamp = activityTimestamp
            self.activityRank = activityRank
            self.muteState = muteState
            self.volume = volume
            self.about = about
            self.joinedVideo = joinedVideo
        }

        public var description: String {
            return "Participant(peer: \(self.id): \(peer?.debugDisplayTitle ?? "User \(self.id)"), ssrc: \(String(describing: self.ssrc))"
        }
        
        public mutating func mergeActivity(from other: Participant, mergeActivityTimestamp: Bool) {
            self.activityRank = other.activityRank
            if mergeActivityTimestamp {
                self.activityTimestamp = other.activityTimestamp
            }
        }
        
        public static func ==(lhs: Participant, rhs: Participant) -> Bool {
            if lhs.id != rhs.id {
                return false
            }
            if lhs.peer != rhs.peer {
                return false
            }
            if lhs.ssrc != rhs.ssrc {
                return false
            }
            if lhs.videoDescription != rhs.videoDescription {
                return false
            }
            if lhs.presentationDescription != rhs.presentationDescription {
                return false
            }
            if lhs.joinTimestamp != rhs.joinTimestamp {
                return false
            }
            if lhs.raiseHandRating != rhs.raiseHandRating {
                return false
            }
            if lhs.hasRaiseHand != rhs.hasRaiseHand {
                return false
            }
            if lhs.activityTimestamp != rhs.activityTimestamp {
                return false
            }
            if lhs.activityRank != rhs.activityRank {
                return false
            }
            if lhs.muteState != rhs.muteState {
                return false
            }
            if lhs.volume != rhs.volume {
                return false
            }
            if lhs.about != rhs.about {
                return false
            }
            if lhs.raiseHandRating != rhs.raiseHandRating {
                return false
            }
            return true
        }
        
        public static func compare(lhs: Participant, rhs: Participant, sortAscending: Bool) -> Bool {
            let lhsCanUnmute = lhs.muteState?.canUnmute ?? true
            let rhsCanUnmute = rhs.muteState?.canUnmute ?? true
            if lhsCanUnmute != rhsCanUnmute {
                return lhsCanUnmute
            }

            if let lhsActivityRank = lhs.activityRank, let rhsActivityRank = rhs.activityRank {
                if lhsActivityRank != rhsActivityRank {
                    return lhsActivityRank < rhsActivityRank
                }
            } else if lhs.activityRank != nil {
                return true
            } else if rhs.activityRank != nil {
                return false
            }
            
            if let lhsActivityTimestamp = lhs.activityTimestamp, let rhsActivityTimestamp = rhs.activityTimestamp {
                if lhsActivityTimestamp != rhsActivityTimestamp {
                    return lhsActivityTimestamp > rhsActivityTimestamp
                }
            } else if lhs.activityTimestamp != nil {
                return true
            } else if rhs.activityTimestamp != nil {
                return false
            }
            
            if let lhsRaiseHandRating = lhs.raiseHandRating, let rhsRaiseHandRating = rhs.raiseHandRating {
                if lhsRaiseHandRating != rhsRaiseHandRating {
                    return lhsRaiseHandRating > rhsRaiseHandRating
                }
            } else if lhs.raiseHandRating != nil {
                return true
            } else if rhs.raiseHandRating != nil {
                return false
            }
            
            if lhs.joinTimestamp != rhs.joinTimestamp {
                if sortAscending {
                    return lhs.joinTimestamp < rhs.joinTimestamp
                } else {
                    return lhs.joinTimestamp > rhs.joinTimestamp
                }
            }
            
            return lhs.id < rhs.id
        }
    }
    
    public struct State: Equatable {
        public struct DefaultParticipantsAreMuted: Equatable {
            public var isMuted: Bool
            public var canChange: Bool
            
            public init(isMuted: Bool, canChange: Bool) {
                self.isMuted = isMuted
                self.canChange = canChange
            }
        }
        
        public var participants: [Participant]
        public var nextParticipantsFetchOffset: String?
        public var adminIds: Set<PeerId>
        public var isCreator: Bool
        public var defaultParticipantsAreMuted: DefaultParticipantsAreMuted
        public var sortAscending: Bool
        public var recordingStartTimestamp: Int32?
        public var title: String?
        public var scheduleTimestamp: Int32?
        public var subscribedToScheduled: Bool
        public var totalCount: Int
        public var isVideoEnabled: Bool
        public var unmutedVideoLimit: Int
        public var isStream: Bool
        public var version: Int32
        
        public mutating func mergeActivity(from other: State, myPeerId: PeerId?, previousMyPeerId: PeerId?, mergeActivityTimestamps: Bool) {
            var indexMap: [PeerId: Int] = [:]
            for i in 0 ..< other.participants.count {
                if let otherParticipantPeer = other.participants[i].peer {
                    indexMap[otherParticipantPeer.id] = i
                }
            }
            
            for i in 0 ..< self.participants.count {
                if let selfParticipantPeer = self.participants[i].peer, let index = indexMap[selfParticipantPeer.id] {
                    self.participants[i].mergeActivity(from: other.participants[index], mergeActivityTimestamp: mergeActivityTimestamps)
                    if selfParticipantPeer.id == myPeerId || selfParticipantPeer.id == previousMyPeerId {
                        self.participants[i].joinTimestamp = other.participants[index].joinTimestamp
                    }
                }
            }
            
            self.participants.sort(by: { GroupCallParticipantsContext.Participant.compare(lhs: $0, rhs: $1, sortAscending: self.sortAscending) })
        }
        
        public init(
            participants: [Participant],
            nextParticipantsFetchOffset: String?,
            adminIds: Set<PeerId>,
            isCreator: Bool,
            defaultParticipantsAreMuted: DefaultParticipantsAreMuted,
            sortAscending: Bool,
            recordingStartTimestamp: Int32?,
            title: String?,
            scheduleTimestamp: Int32?,
            subscribedToScheduled: Bool,
            totalCount: Int,
            isVideoEnabled: Bool,
            unmutedVideoLimit: Int,
            isStream: Bool,
            version: Int32
        ) {
            self.participants = participants
            self.nextParticipantsFetchOffset = nextParticipantsFetchOffset
            self.adminIds = adminIds
            self.isCreator = isCreator
            self.defaultParticipantsAreMuted = defaultParticipantsAreMuted
            self.sortAscending = sortAscending
            self.recordingStartTimestamp = recordingStartTimestamp
            self.title = title
            self.scheduleTimestamp = scheduleTimestamp
            self.subscribedToScheduled = subscribedToScheduled
            self.totalCount = totalCount
            self.isVideoEnabled = isVideoEnabled
            self.unmutedVideoLimit = unmutedVideoLimit
            self.isStream = isStream
            self.version = version
        }
    }
    
    private struct OverlayState: Equatable {
        struct MuteStateChange: Equatable {
            var state: Participant.MuteState?
            var volume: Int32?
            var disposable: Disposable
            
            static func ==(lhs: MuteStateChange, rhs: MuteStateChange) -> Bool {
                if lhs.state != rhs.state {
                    return false
                }
                if lhs.volume != rhs.volume {
                    return false
                }
                if lhs.disposable !== rhs.disposable {
                    return false
                }
                return true
            }
        }
        
        var pendingMuteStateChanges: [PeerId: MuteStateChange] = [:]
        
        var hasLocalVideo: PeerId? = nil
        
        var isEmpty: Bool {
            if !self.pendingMuteStateChanges.isEmpty {
                return false
            }
            if self.hasLocalVideo != nil {
                return false
            }
            return true
        }
    }
    
    private final class ResolvedBlockchainParticipant: Equatable {
        let participant: ConferenceCallE2EContext.BlockchainParticipant
        let peer: EnginePeer?

        init(participant: ConferenceCallE2EContext.BlockchainParticipant, peer: EnginePeer?) {
            self.participant = participant
            self.peer = peer
        }

        static func ==(lhs: ResolvedBlockchainParticipant, rhs: ResolvedBlockchainParticipant) -> Bool {
            return lhs.participant == rhs.participant && lhs.peer == rhs.peer
        }
    }
    
    private struct BlockchainState: Equatable {
        var blockchainParticipants: [ResolvedBlockchainParticipant]
    }
    
    private struct InternalState: Equatable {
        var state: State
        var overlayState: OverlayState
        var blockchainState: BlockchainState
    }
    
    public enum Update {
        public struct StateUpdate {
            public struct ParticipantUpdate {
                public enum ParticipationStatusChange {
                    case none
                    case joined
                    case left
                }
                
                public var peerId: PeerId
                public var ssrc: UInt32?
                public var videoDescription: GroupCallParticipantsContext.Participant.VideoDescription?
                public var presentationDescription: GroupCallParticipantsContext.Participant.VideoDescription?
                public var joinTimestamp: Int32
                public var activityTimestamp: Double?
                public var raiseHandRating: Int64?
                public var muteState: Participant.MuteState?
                public var participationStatusChange: ParticipationStatusChange
                public var volume: Int32?
                public var about: String?
                public var joinedVideo: Bool
                public var isMin: Bool
                
                init(
                    peerId: PeerId,
                    ssrc: UInt32?,
                    videoDescription: GroupCallParticipantsContext.Participant.VideoDescription?,
                    presentationDescription: GroupCallParticipantsContext.Participant.VideoDescription?,
                    joinTimestamp: Int32,
                    activityTimestamp: Double?,
                    raiseHandRating: Int64?,
                    muteState: Participant.MuteState?,
                    participationStatusChange: ParticipationStatusChange,
                    volume: Int32?,
                    about: String?,
                    joinedVideo: Bool,
                    isMin: Bool
                ) {
                    self.peerId = peerId
                    self.ssrc = ssrc
                    self.videoDescription = videoDescription
                    self.presentationDescription = presentationDescription
                    self.joinTimestamp = joinTimestamp
                    self.activityTimestamp = activityTimestamp
                    self.raiseHandRating = raiseHandRating
                    self.muteState = muteState
                    self.participationStatusChange = participationStatusChange
                    self.volume = volume
                    self.about = about
                    self.joinedVideo = joinedVideo
                    self.isMin = isMin
                }
            }
            
            public var participantUpdates: [ParticipantUpdate]
            public var version: Int32
            
            public var removePendingMuteStates: Set<PeerId>
        }
        
        case state(update: StateUpdate)
        case call(isTerminated: Bool, defaultParticipantsAreMuted: State.DefaultParticipantsAreMuted, title: String?, recordingStartTimestamp: Int32?, scheduleTimestamp: Int32?, isVideoEnabled: Bool, participantCount: Int?)
        case conferenceChainBlocks(subChainId: Int, blocks: [Data], nextOffset: Int)
    }
    
    public final class MemberEvent {
        public let peerId: PeerId
        public let canUnmute: Bool
        public let joined: Bool
        
        public init(peerId: PeerId, canUnmute: Bool, joined: Bool) {
            self.peerId = peerId
            self.canUnmute = canUnmute
            self.joined = joined
        }
    }
    
    private let account: Account
    private let peerId: PeerId?
    public let myPeerId: PeerId
    public let id: Int64
    public let reference: InternalGroupCallReference
    
    private var hasReceivedSpeakingParticipantsReport: Bool = false
    
    private var stateValue: InternalState {
        didSet {
            if self.stateValue != oldValue {
                self.statePromise.set(self.stateValue)
            }
        }
    }
    private let statePromise: ValuePromise<InternalState>
    
    public var immediateState: State?
    
    public var state: Signal<State, NoError> {
        let accountPeerId = self.account.peerId
        let myPeerId = self.myPeerId
        return self.statePromise.get()
        |> map { state -> State in
            var publicState = state.state
            var sortAgain = false
            var canSeeHands = state.state.isCreator || state.state.adminIds.contains(accountPeerId)
            for participant in publicState.participants {
                if participant.id == .peer(myPeerId) {
                    if let muteState = participant.muteState {
                        if muteState.canUnmute {
                            canSeeHands = true
                        }
                    } else {
                        canSeeHands = true
                    }
                    break
                }
            }
            for i in 0 ..< publicState.participants.count {
                if let participantPeer = publicState.participants[i].peer, let pendingMuteState = state.overlayState.pendingMuteStateChanges[participantPeer.id] {
                    publicState.participants[i].muteState = pendingMuteState.state
                    publicState.participants[i].volume = pendingMuteState.volume
                }
                if !canSeeHands && publicState.participants[i].raiseHandRating != nil {
                    publicState.participants[i].raiseHandRating = nil
                    sortAgain = true
                }
                
                //TODO:wip-release
                /*if let hasLocalVideoPeerId = state.overlayState.hasLocalVideo, hasLocalVideoPeerId == publicState.participants[i].peer.id {
                    if publicState.participants[i].videoDescription == nil {
                        publicState.participants[i].videoDescription = GroupCallParticipantsContext.Participant.VideoDescription(endpointId: "_local", ssrcGroups: [], audioSsrc: nil, isPaused: false)
                    }
                }*/
            }
            if sortAgain {
                publicState.participants.sort(by: { GroupCallParticipantsContext.Participant.compare(lhs: $0, rhs: $1, sortAscending: publicState.sortAscending) })
            }
            for blockchainParticipant in state.blockchainState.blockchainParticipants {
                let blockchainParticipantPeerId = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(blockchainParticipant.participant.userId))
                if !publicState.participants.contains(where: { $0.id == .peer(blockchainParticipantPeerId) }) {
                    publicState.participants.append(Participant(
                        id: .peer(blockchainParticipantPeerId),
                        peer: blockchainParticipant.peer,
                        ssrc: nil,
                        videoDescription: nil,
                        presentationDescription: nil,
                        joinTimestamp: 0,
                        raiseHandRating: nil,
                        hasRaiseHand: false,
                        activityTimestamp: nil,
                        activityRank: nil,
                        muteState: nil,
                        volume: nil,
                        about: nil,
                        joinedVideo: false
                    ))
                }
            }
            return publicState
        }
        |> beforeNext { [weak self] next in
            Queue.mainQueue().async {
                self?.immediateState = next
            }
        }
    }
    
    private var activeSpeakersValue: Set<PeerId> = Set() {
        didSet {
            if self.activeSpeakersValue != oldValue {
                self.activeSpeakersPromise.set(self.activeSpeakersValue)
            }
        }
    }
    private let activeSpeakersPromise = ValuePromise<Set<PeerId>>(Set())
    public var activeSpeakers: Signal<Set<PeerId>, NoError> {
        return self.activeSpeakersPromise.get()
    }
    
    private let memberEventsPipe = ValuePipe<MemberEvent>()
    public var memberEvents: Signal<MemberEvent, NoError> {
        return self.memberEventsPipe.signal()
    }
    
    private let isFailedEventPromise = ValuePromise<Bool>(false, ignoreRepeated: true)
    public var isFailedEvent: Signal<Bool, NoError> {
        return self.isFailedEventPromise.get()
    }
    
    private var updateQueue: [Update.StateUpdate] = []
    private var isProcessingUpdate: Bool = false
    private let disposable = MetaDisposable()
    
    private let updatesDisposable = MetaDisposable()
    private var activitiesDisposable: Disposable?
    
    private var isLoadingMore: Bool = false
    private var shouldResetStateFromServer: Bool = false
    private var missingSsrcs = Set<UInt32>()

    private var activityRankResetTimer: SwiftSignalKit.Timer?
    
    private let updateDefaultMuteDisposable = MetaDisposable()
    private let resetInviteLinksDisposable = MetaDisposable()
    private let updateShouldBeRecordingDisposable = MetaDisposable()
    private let subscribeDisposable = MetaDisposable()
    
    private var localVideoIsMuted: Bool? = nil
    private var localIsVideoPaused: Bool? = nil
    private var localIsPresentationPaused: Bool? = nil
    public struct ServiceState {
        fileprivate var nextActivityRank: Int = 0
    }

    public private(set) var serviceState: ServiceState
    
    private var e2eStateUpdateDisposable: Disposable?
    private var e2eIsFailedDisposable: Disposable?
    private var pendingBlockchainState: [ResolvedBlockchainParticipant]?
    private var pendingApplyBlockchainStateTimer: Foundation.Timer?
    
    init(account: Account, peerId: PeerId?, myPeerId: PeerId, id: Int64, reference: InternalGroupCallReference, state: State, previousServiceState: ServiceState?, e2eContext: ConferenceCallE2EContext?) {
        self.account = account
        self.peerId = peerId
        self.myPeerId = myPeerId
        self.id = id
        self.reference = reference
        self.stateValue = InternalState(state: state, overlayState: OverlayState(), blockchainState: BlockchainState(blockchainParticipants: []))
        self.statePromise = ValuePromise<InternalState>(self.stateValue)
        self.serviceState = previousServiceState ?? ServiceState()
        
        self.updatesDisposable.set((self.account.stateManager.groupCallParticipantUpdates
        |> deliverOnMainQueue).start(next: { [weak self] updates in
            guard let strongSelf = self else {
                return
            }
            var filteredUpdates: [Update] = []
            for (callId, update) in updates {
                if callId == id {
                    filteredUpdates.append(update)
                }
            }
            if !filteredUpdates.isEmpty {
                strongSelf.addUpdates(updates: filteredUpdates)
            }
        }))
        
        if let peerId {
            let activityCategory: PeerActivitySpace.Category = .voiceChat
            self.activitiesDisposable = (self.account.peerInputActivities(peerId: PeerActivitySpace(peerId: peerId, category: activityCategory))
            |> deliverOnMainQueue).start(next: { [weak self] activities in
                guard let strongSelf = self else {
                    return
                }
                
                let peerIds = Set(activities.map { item -> PeerId in
                    item.0
                })
                strongSelf.activeSpeakersValue = peerIds
                
                if !strongSelf.hasReceivedSpeakingParticipantsReport {
                    var updatedParticipants = strongSelf.stateValue.state.participants
                    var indexMap: [PeerId: Int] = [:]
                    for i in 0 ..< updatedParticipants.count {
                        if let participantPeer = updatedParticipants[i].peer {
                            indexMap[participantPeer.id] = i
                        }
                    }
                    var updated = false
                    
                    for (activityPeerId, activity) in activities {
                        if case let .speakingInGroupCall(intTimestamp) = activity {
                            let timestamp = Double(intTimestamp)
                            
                            if let index = indexMap[activityPeerId] {
                                if let activityTimestamp = updatedParticipants[index].activityTimestamp {
                                    if activityTimestamp < timestamp {
                                        updatedParticipants[index].activityTimestamp = timestamp
                                        updated = true
                                    }
                                } else {
                                    updatedParticipants[index].activityTimestamp = timestamp
                                    updated = true
                                }
                            }
                        }
                    }
                    
                    if updated {
                        updatedParticipants.sort(by: { GroupCallParticipantsContext.Participant.compare(lhs: $0, rhs: $1, sortAscending: strongSelf.stateValue.state.sortAscending) })
                        
                        strongSelf.stateValue = InternalState(
                            state: State(
                                participants: updatedParticipants,
                                nextParticipantsFetchOffset: strongSelf.stateValue.state.nextParticipantsFetchOffset,
                                adminIds: strongSelf.stateValue.state.adminIds,
                                isCreator: strongSelf.stateValue.state.isCreator,
                                defaultParticipantsAreMuted: strongSelf.stateValue.state.defaultParticipantsAreMuted,
                                sortAscending: strongSelf.stateValue.state.sortAscending,
                                recordingStartTimestamp: strongSelf.stateValue.state.recordingStartTimestamp,
                                title: strongSelf.stateValue.state.title,
                                scheduleTimestamp: strongSelf.stateValue.state.scheduleTimestamp,
                                subscribedToScheduled: strongSelf.stateValue.state.subscribedToScheduled,
                                totalCount: strongSelf.stateValue.state.totalCount,
                                isVideoEnabled: strongSelf.stateValue.state.isVideoEnabled,
                                unmutedVideoLimit: strongSelf.stateValue.state.unmutedVideoLimit,
                                isStream: strongSelf.stateValue.state.isStream,
                                version: strongSelf.stateValue.state.version
                            ),
                            overlayState: strongSelf.stateValue.overlayState,
                            blockchainState: strongSelf.stateValue.blockchainState
                        )
                    }
                }
            })
        }
        
        self.activityRankResetTimer = SwiftSignalKit.Timer(timeout: 10.0, repeat: true, completion: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            
            var updated = false
            let timestamp = CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970
            
            for i in 0 ..< strongSelf.stateValue.state.participants.count {
                if strongSelf.stateValue.state.participants[i].activityRank != nil {
                    var clearRank = false
                    if let activityTimestamp = strongSelf.stateValue.state.participants[i].activityTimestamp {
                        if activityTimestamp < timestamp - 60.0 {
                            clearRank = true
                        }
                    } else {
                        clearRank = true
                    }
                    if clearRank {
                        updated = true
                        strongSelf.stateValue.state.participants[i].activityRank = nil
                    }
                }
            }
            if updated {
                strongSelf.stateValue.state.participants.sort(by: { GroupCallParticipantsContext.Participant.compare(lhs: $0, rhs: $1, sortAscending: strongSelf.stateValue.state.sortAscending) })
            }
        }, queue: .mainQueue())
        self.activityRankResetTimer?.start()
        
        if let e2eContext {
            let postbox = self.account.postbox
            self.e2eStateUpdateDisposable = (e2eContext.blockchainParticipants
            |> mapToSignal { value -> Signal<[ResolvedBlockchainParticipant], NoError> in
                return postbox.transaction { transaction -> [ResolvedBlockchainParticipant] in
                    var result: [ResolvedBlockchainParticipant] = []
                    for participant in value {
                        let blockchainParticipantPeerId = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(participant.userId))
                        if let peer = transaction.getPeer(blockchainParticipantPeerId) {
                            result.append(ResolvedBlockchainParticipant(participant: participant, peer: EnginePeer(peer)))
                        } else {
                            result.append(ResolvedBlockchainParticipant(participant: participant, peer: nil))
                        }
                    }
                    return result
                }
            }
            |> deliverOnMainQueue).startStrict(next: { [weak self] blockchainParticipants in
                guard let self else {
                    return
                }
                
                self.pendingBlockchainState = blockchainParticipants
                
                self.pendingApplyBlockchainStateTimer?.invalidate()
                self.pendingApplyBlockchainStateTimer = nil
                
                var hasUnknownParticipants: Bool = false
                for blockchainParticipant in blockchainParticipants {
                    if !self.stateValue.state.participants.contains(where: { $0.id == .peer(EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(blockchainParticipant.participant.userId))) }) {
                        hasUnknownParticipants = true
                        break
                    }
                }
                if hasUnknownParticipants {
                    self.pendingApplyBlockchainStateTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false, block: { [weak self] _ in
                        guard let self else {
                            return
                        }
                        self.applyPendingBlockchainState()
                    })
                } else {
                    self.applyPendingBlockchainState()
                }
            })
            
            self.e2eIsFailedDisposable = (e2eContext.isFailed
            |> filter { $0 }
            |> take(1)
            |> deliverOnMainQueue).startStrict(next: { [weak self] isFailed in
                guard let self else {
                    return
                }
                if isFailed {
                    self.isFailedEventPromise.set(true)
                }
            })
        }
    }
    
    deinit {
        self.disposable.dispose()
        self.updatesDisposable.dispose()
        self.activitiesDisposable?.dispose()
        self.updateDefaultMuteDisposable.dispose()
        self.updateShouldBeRecordingDisposable.dispose()
        self.activityRankResetTimer?.invalidate()
        self.resetInviteLinksDisposable.dispose()
        self.subscribeDisposable.dispose()
        self.e2eStateUpdateDisposable?.dispose()
        self.e2eIsFailedDisposable?.dispose()
        self.pendingApplyBlockchainStateTimer?.invalidate()
    }
    
    private func applyPendingBlockchainState() {
        self.pendingApplyBlockchainStateTimer?.invalidate()
        self.pendingApplyBlockchainStateTimer = nil

        if let pendingBlockchainState = self.pendingBlockchainState {
            self.pendingBlockchainState = nil

            self.stateValue.blockchainState = BlockchainState(blockchainParticipants: pendingBlockchainState)
        }
    }
    
    public func addUpdates(updates: [Update]) {
        var stateUpdates: [Update.StateUpdate] = []
        for update in updates {
            if case let .state(update) = update {
                stateUpdates.append(update)
            } else if case let .call(_, defaultParticipantsAreMuted, title, recordingStartTimestamp, scheduleTimestamp, isVideoEnabled, participantsCount) = update {
                var state = self.stateValue.state
                state.defaultParticipantsAreMuted = defaultParticipantsAreMuted
                state.recordingStartTimestamp = recordingStartTimestamp
                state.title = title
                state.scheduleTimestamp = scheduleTimestamp
                state.isVideoEnabled = isVideoEnabled
                if let participantsCount = participantsCount {
                    state.totalCount = participantsCount
                }
                
                self.stateValue.state = state
            }
        }
        
        if !stateUpdates.isEmpty {
            self.updateQueue.append(contentsOf: stateUpdates)
            self.beginProcessingUpdatesIfNeeded()
        }
    }
    
    public func removeLocalPeerId() {
        var state = self.stateValue.state
        
        state.participants.removeAll(where: { $0.id == .peer(self.myPeerId) })
        
        self.stateValue.state = state
    }
    
    private func takeNextActivityRank() -> Int {
        let value = self.serviceState.nextActivityRank
        self.serviceState.nextActivityRank += 1
        return value
    }

    public func updateAdminIds(_ adminIds: Set<PeerId>) {
        if self.stateValue.state.adminIds != adminIds {
            self.stateValue.state.adminIds = adminIds
        }
    }
    
    public func reportSpeakingParticipants(ids: [PeerId: UInt32]) {
        if !ids.isEmpty {
            self.hasReceivedSpeakingParticipantsReport = true
        }
        
        let strongSelf = self
        
        var updatedParticipants = strongSelf.stateValue.state.participants
        var indexMap: [PeerId: Int] = [:]
        for i in 0 ..< updatedParticipants.count {
            if let participantPeer = updatedParticipants[i].peer {
                indexMap[participantPeer.id] = i
            }
        }
        var updated = false
        
        let timestamp = CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970
        
        for (activityPeerId, _) in ids {
            if let index = indexMap[activityPeerId] {
                var updateTimestamp = false
                if let activityTimestamp = updatedParticipants[index].activityTimestamp {
                    if activityTimestamp < timestamp {
                        updateTimestamp = true
                    }
                } else {
                    updateTimestamp = true
                }
                if updateTimestamp {
                    updatedParticipants[index].activityTimestamp = timestamp
                    if updatedParticipants[index].activityRank == nil {
                        updatedParticipants[index].activityRank = self.takeNextActivityRank()
                    }
                    updated = true
                }
            }
        }
        
        if updated {
            updatedParticipants.sort(by: { GroupCallParticipantsContext.Participant.compare(lhs: $0, rhs: $1, sortAscending: strongSelf.stateValue.state.sortAscending) })
            
            strongSelf.stateValue = InternalState(
                state: State(
                    participants: updatedParticipants,
                    nextParticipantsFetchOffset: strongSelf.stateValue.state.nextParticipantsFetchOffset,
                    adminIds: strongSelf.stateValue.state.adminIds,
                    isCreator: strongSelf.stateValue.state.isCreator,
                    defaultParticipantsAreMuted: strongSelf.stateValue.state.defaultParticipantsAreMuted,
                    sortAscending: strongSelf.stateValue.state.sortAscending,
                    recordingStartTimestamp: strongSelf.stateValue.state.recordingStartTimestamp,
                    title: strongSelf.stateValue.state.title,
                    scheduleTimestamp: strongSelf.stateValue.state.scheduleTimestamp,
                    subscribedToScheduled: strongSelf.stateValue.state.subscribedToScheduled,
                    totalCount: strongSelf.stateValue.state.totalCount,
                    isVideoEnabled: strongSelf.stateValue.state.isVideoEnabled,
                    unmutedVideoLimit: strongSelf.stateValue.state.unmutedVideoLimit,
                    isStream: strongSelf.stateValue.state.isStream,
                    version: strongSelf.stateValue.state.version
                ),
                overlayState: strongSelf.stateValue.overlayState,
                blockchainState: strongSelf.stateValue.blockchainState
            )
        }
        
        self.ensureHaveParticipants(ssrcs: Set(ids.map { $0.1 }))
    }
    
    public func ensureHaveParticipants(ssrcs: Set<UInt32>) {
        var missingSsrcs = Set<UInt32>()
        
        var existingSsrcs = Set<UInt32>()
        for participant in self.stateValue.state.participants {
            if let ssrc = participant.ssrc {
                existingSsrcs.insert(ssrc)
            }
            if let presentationDescription = participant.presentationDescription, let presentationAudioSsrc = presentationDescription.audioSsrc {
                existingSsrcs.insert(presentationAudioSsrc)
            }
        }
        
        for ssrc in ssrcs {
            if !existingSsrcs.contains(ssrc) {
                missingSsrcs.insert(ssrc)
            }
        }
        
        if !missingSsrcs.isEmpty {
            self.missingSsrcs.formUnion(missingSsrcs)
            self.loadMissingSsrcs()
        }
    }
    
    private func loadMissingSsrcs() {
        if self.missingSsrcs.isEmpty {
            return
        }
        if self.isLoadingMore {
            return
        }
        self.isLoadingMore = true
        
        let ssrcs = self.missingSsrcs

        Logger.shared.log("GroupCallParticipantsContext", "will request ssrcs=\(ssrcs)")
        
        self.disposable.set((_internal_getGroupCallParticipants(account: self.account, reference: self.reference, offset: "", ssrcs: Array(ssrcs), limit: 100, sortAscending: true)
        |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isLoadingMore = false
            
            strongSelf.missingSsrcs.subtract(ssrcs)

            Logger.shared.log("GroupCallParticipantsContext", "did receive response for ssrcs=\(ssrcs), \(state.participants)")
            
            var updatedState = strongSelf.stateValue.state
            
            updatedState.participants = mergeAndSortParticipants(current: updatedState.participants, with: state.participants, sortAscending: updatedState.sortAscending)
            
            updatedState.totalCount = max(updatedState.totalCount, state.totalCount)
            updatedState.version = max(updatedState.version, updatedState.version)
            
            strongSelf.stateValue.state = updatedState
            
            if strongSelf.shouldResetStateFromServer {
                strongSelf.resetStateFromServer()
            } else {
                strongSelf.loadMissingSsrcs()
            }
        }))
    }
    
    private func beginProcessingUpdatesIfNeeded() {
        if self.isProcessingUpdate {
            return
        }
        if self.updateQueue.isEmpty {
            return
        }
        self.isProcessingUpdate = true
        let update = self.updateQueue.removeFirst()
        self.processUpdate(update: update)
    }
    
    private func endedProcessingUpdate() {
        assert(self.isProcessingUpdate)
        self.isProcessingUpdate = false
        self.beginProcessingUpdatesIfNeeded()
    }
    
    private func processUpdate(update: Update.StateUpdate) {
        if update.version < self.stateValue.state.version {
            for peerId in update.removePendingMuteStates {
                self.stateValue.overlayState.pendingMuteStateChanges.removeValue(forKey: peerId)
            }
            self.endedProcessingUpdate()
            return
        }
        
        if update.version > self.stateValue.state.version + 1 {
            for peerId in update.removePendingMuteStates {
                self.stateValue.overlayState.pendingMuteStateChanges.removeValue(forKey: peerId)
            }
            self.resetStateFromServer()
            return
        }
        
        let isVersionUpdate = update.version != self.stateValue.state.version
        
        let _ = (self.account.postbox.transaction { transaction -> [PeerId: Peer] in
            var peers: [PeerId: Peer] = [:]
            
            for participantUpdate in update.participantUpdates {
                if let peer = transaction.getPeer(participantUpdate.peerId) {
                    peers[peer.id] = peer
                }
            }
            
            return peers
        }
        |> deliverOnMainQueue).start(next: { [weak self] peers in
            guard let strongSelf = self else {
                return
            }
            
            var updatedParticipants = strongSelf.stateValue.state.participants
            var updatedTotalCount = strongSelf.stateValue.state.totalCount
            
            for participantUpdate in update.participantUpdates {
                if case .left = participantUpdate.participationStatusChange {
                    if let index = updatedParticipants.firstIndex(where: { $0.id == .peer(participantUpdate.peerId) }) {
                        updatedParticipants.remove(at: index)
                        updatedTotalCount = max(0, updatedTotalCount - 1)
                        strongSelf.memberEventsPipe.putNext(MemberEvent(peerId: participantUpdate.peerId, canUnmute: false, joined: false))
                    } else if isVersionUpdate {
                        updatedTotalCount = max(0, updatedTotalCount - 1)
                    }
                } else {
                    guard let peer = peers[participantUpdate.peerId] else {
                        assertionFailure()
                        continue
                    }
                    var previousJoinTimestamp: Int32?
                    var previousActivityTimestamp: Double?
                    var previousActivityRank: Int?
                    var previousMuteState: GroupCallParticipantsContext.Participant.MuteState?
                    var previousVolume: Int32?
                    if let index = updatedParticipants.firstIndex(where: { $0.id == .peer(participantUpdate.peerId) }) {
                        previousJoinTimestamp = updatedParticipants[index].joinTimestamp
                        previousActivityTimestamp = updatedParticipants[index].activityTimestamp
                        previousActivityRank = updatedParticipants[index].activityRank
                        previousMuteState = updatedParticipants[index].muteState
                        previousVolume = updatedParticipants[index].volume
                        updatedParticipants.remove(at: index)
                    } else if case .joined = participantUpdate.participationStatusChange {
                        updatedTotalCount += 1
                        strongSelf.memberEventsPipe.putNext(MemberEvent(peerId: participantUpdate.peerId, canUnmute: participantUpdate.muteState?.canUnmute ?? true, joined: true))
                    }

                    var activityTimestamp: Double?
                    if let previousActivityTimestamp = previousActivityTimestamp, let updatedActivityTimestamp = participantUpdate.activityTimestamp {
                        activityTimestamp = max(updatedActivityTimestamp, previousActivityTimestamp)
                    } else {
                        activityTimestamp = participantUpdate.activityTimestamp ?? previousActivityTimestamp
                    }

                    if let muteState = participantUpdate.muteState, !muteState.canUnmute {
                        previousActivityRank = nil
                        activityTimestamp = nil
                    }

                    var volume = participantUpdate.volume
                    var muteState = participantUpdate.muteState
                    if participantUpdate.isMin {
                        if let previousMuteState = previousMuteState {
                            if previousMuteState.mutedByYou {
                                muteState = previousMuteState
                            }
                        }
                        if let previousVolume = previousVolume {
                            volume = previousVolume
                        }
                    }
                    let participant = Participant(
                        id: .peer(peer.id),
                        peer: EnginePeer(peer),
                        ssrc: participantUpdate.ssrc,
                        videoDescription: participantUpdate.videoDescription,
                        presentationDescription: participantUpdate.presentationDescription,
                        joinTimestamp: previousJoinTimestamp ?? participantUpdate.joinTimestamp,
                        raiseHandRating: participantUpdate.raiseHandRating,
                        hasRaiseHand: participantUpdate.raiseHandRating != nil,
                        activityTimestamp: activityTimestamp,
                        activityRank: previousActivityRank,
                        muteState: muteState,
                        volume: volume,
                        about: participantUpdate.about,
                        joinedVideo: participantUpdate.joinedVideo
                    )
                    updatedParticipants.append(participant)
                }
            }
            
            updatedTotalCount = max(updatedTotalCount, updatedParticipants.count)
            
            var updatedOverlayState = strongSelf.stateValue.overlayState
            for peerId in update.removePendingMuteStates {
                updatedOverlayState.pendingMuteStateChanges.removeValue(forKey: peerId)
            }
            
            let nextParticipantsFetchOffset = strongSelf.stateValue.state.nextParticipantsFetchOffset
            let adminIds = strongSelf.stateValue.state.adminIds
            let isCreator = strongSelf.stateValue.state.isCreator
            let defaultParticipantsAreMuted = strongSelf.stateValue.state.defaultParticipantsAreMuted
            let recordingStartTimestamp = strongSelf.stateValue.state.recordingStartTimestamp
            let title = strongSelf.stateValue.state.title
            let scheduleTimestamp = strongSelf.stateValue.state.scheduleTimestamp
            let subscribedToScheduled = strongSelf.stateValue.state.subscribedToScheduled
            let isVideoEnabled = strongSelf.stateValue.state.isVideoEnabled
            let isStream = strongSelf.stateValue.state.isStream
            let unmutedVideoLimit = strongSelf.stateValue.state.unmutedVideoLimit
            
            updatedParticipants.sort(by: { GroupCallParticipantsContext.Participant.compare(lhs: $0, rhs: $1, sortAscending: strongSelf.stateValue.state.sortAscending) })
            
            strongSelf.stateValue = InternalState(
                state: State(
                    participants: updatedParticipants,
                    nextParticipantsFetchOffset: nextParticipantsFetchOffset,
                    adminIds: adminIds,
                    isCreator: isCreator,
                    defaultParticipantsAreMuted: defaultParticipantsAreMuted,
                    sortAscending: strongSelf.stateValue.state.sortAscending,
                    recordingStartTimestamp: recordingStartTimestamp,
                    title: title,
                    scheduleTimestamp: scheduleTimestamp,
                    subscribedToScheduled: subscribedToScheduled,
                    totalCount: updatedTotalCount,
                    isVideoEnabled: isVideoEnabled,
                    unmutedVideoLimit: unmutedVideoLimit,
                    isStream: isStream,
                    version: update.version
                ),
                overlayState: updatedOverlayState,
                blockchainState: strongSelf.stateValue.blockchainState
            )
            
            strongSelf.endedProcessingUpdate()
        })
    }
    
    private func resetStateFromServer() {
        if self.isLoadingMore {
            self.shouldResetStateFromServer = true
            return
        }
        
        self.isLoadingMore = true
        
        self.updateQueue.removeAll()
        
        self.disposable.set((_internal_getGroupCallParticipants(account: self.account, reference: self.reference, offset: "", ssrcs: [], limit: 100, sortAscending: self.stateValue.state.sortAscending)
        |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isLoadingMore = false
            strongSelf.shouldResetStateFromServer = false
            var state = state
            state.adminIds = strongSelf.stateValue.state.adminIds
            state.isCreator = strongSelf.stateValue.state.isCreator
            state.defaultParticipantsAreMuted = strongSelf.stateValue.state.defaultParticipantsAreMuted
            state.title = strongSelf.stateValue.state.title
            state.recordingStartTimestamp = strongSelf.stateValue.state.recordingStartTimestamp
            state.scheduleTimestamp = strongSelf.stateValue.state.scheduleTimestamp
            state.mergeActivity(from: strongSelf.stateValue.state, myPeerId: nil, previousMyPeerId: nil, mergeActivityTimestamps: false)
            strongSelf.stateValue.state = state
            strongSelf.endedProcessingUpdate()
        }))
    }
    
    public func updateMuteState(peerId: PeerId, muteState: Participant.MuteState?, volume: Int32?, raiseHand: Bool?) {
        if let current = self.stateValue.overlayState.pendingMuteStateChanges[peerId] {
            if current.state == muteState {
                return
            }
            current.disposable.dispose()
            self.stateValue.overlayState.pendingMuteStateChanges.removeValue(forKey: peerId)
        }
        
        for participant in self.stateValue.state.participants {
            if participant.id == .peer(peerId) {
                var raiseHandEqual: Bool = true
                if let raiseHand = raiseHand {
                    raiseHandEqual = (participant.raiseHandRating == nil && !raiseHand) ||
                        (participant.raiseHandRating != nil && raiseHand)
                }
                if participant.muteState == muteState && participant.volume == volume && raiseHandEqual {
                    return
                }
            }
        }
        
        let disposable = MetaDisposable()
        if raiseHand == nil {
            self.stateValue.overlayState.pendingMuteStateChanges[peerId] = OverlayState.MuteStateChange(
                state: muteState,
                volume: volume,
                disposable: disposable
            )
        }
        
        let account = self.account
        let id = self.id
        let reference = self.reference
        let myPeerId = self.myPeerId
        
        let signal: Signal<Api.Updates?, NoError> = self.account.postbox.transaction { transaction -> Api.InputPeer? in
            return transaction.getPeer(peerId).flatMap(apiInputPeer)
        }
        |> mapToSignal { inputPeer -> Signal<Api.Updates?, NoError> in
            guard let inputPeer = inputPeer else {
                return .single(nil)
            }
            var flags: Int32 = 0
            if let volume = volume, volume > 0 {
                flags |= 1 << 1
            }
            var muted: Api.Bool?
            if let muteState = muteState, (!muteState.canUnmute || peerId == myPeerId || muteState.mutedByYou) {
                flags |= 1 << 0
                muted = .boolTrue
            } else if peerId == myPeerId {
                flags |= 1 << 0
                muted = .boolFalse
            }
            let raiseHandApi: Api.Bool?
            if let raiseHand = raiseHand {
                flags |= 1 << 2
                raiseHandApi = raiseHand ? .boolTrue : .boolFalse
            } else {
                raiseHandApi = nil
            }
                        
            return account.network.request(Api.functions.phone.editGroupCallParticipant(flags: flags, call: reference.apiInputGroupCall, participant: inputPeer, muted: muted, volume: volume, raiseHand: raiseHandApi, videoStopped: nil, videoPaused: nil, presentationPaused: nil))
            |> map(Optional.init)
            |> `catch` { _ -> Signal<Api.Updates?, NoError> in
                return .single(nil)
            }
        }
        
        disposable.set((signal
        |> deliverOnMainQueue).start(next: { [weak self] updates in
            guard let strongSelf = self else {
                return
            }
            
            if let updates = updates {
                var stateUpdates: [GroupCallParticipantsContext.Update] = []
                
                loop: for update in updates.allUpdates {
                    switch update {
                    case let .updateGroupCallParticipants(call, participants, version):
                        switch call {
                        case let .inputGroupCall(updateCallId, _):
                            if updateCallId != id {
                                continue loop
                            }
                        case .inputGroupCallSlug, .inputGroupCallInviteMessage:
                            continue loop
                        }
                        stateUpdates.append(.state(update: GroupCallParticipantsContext.Update.StateUpdate(participants: participants, version: version, removePendingMuteStates: [peerId])))
                    default:
                        break
                    }
                }
                
                strongSelf.addUpdates(updates: stateUpdates)
                
                strongSelf.account.stateManager.addUpdates(updates)
            } else {
                strongSelf.stateValue.overlayState.pendingMuteStateChanges.removeValue(forKey: peerId)
            }
        }))
    }

    public func updateVideoState(peerId: PeerId, isVideoMuted: Bool?, isVideoPaused: Bool?, isPresentationPaused: Bool?) {
        if self.localVideoIsMuted == isVideoMuted && self.localIsVideoPaused == isVideoPaused && self.localIsPresentationPaused == isPresentationPaused {
            return
        }
        self.localVideoIsMuted = isVideoMuted
        self.localIsVideoPaused = isVideoPaused
        self.localIsPresentationPaused = isPresentationPaused
        
        //TODO:wip-release
        /*if let isVideoMuted {
            self.stateValue.overlayState.hasLocalVideo = isVideoMuted ? nil : peerId
        }*/
        
        let disposable = MetaDisposable()

        let account = self.account
        let id = self.id
        let reference = self.reference

        let signal: Signal<Api.Updates?, NoError> = self.account.postbox.transaction { transaction -> Api.InputPeer? in
            return transaction.getPeer(peerId).flatMap(apiInputPeer)
        }
        |> mapToSignal { inputPeer -> Signal<Api.Updates?, NoError> in
            guard let inputPeer = inputPeer else {
                return .single(nil)
            }
            var flags: Int32 = 0
            var videoMuted: Api.Bool?

            if let isVideoMuted = isVideoMuted {
                videoMuted = isVideoMuted ? .boolTrue : .boolFalse
                flags |= 1 << 3
            }

            var videoPaused: Api.Bool?
            if isVideoMuted != nil, let isVideoPaused = isVideoPaused {
                videoPaused = isVideoPaused ? .boolTrue : .boolFalse
                flags |= 1 << 4
            }
            var presentationPaused: Api.Bool?

            if let isPresentationPaused = isPresentationPaused {
                presentationPaused = isPresentationPaused ? .boolTrue : .boolFalse
                flags |= 1 << 5
            }

            return account.network.request(Api.functions.phone.editGroupCallParticipant(flags: flags, call: reference.apiInputGroupCall, participant: inputPeer, muted: nil, volume: nil, raiseHand: nil, videoStopped: videoMuted, videoPaused: videoPaused, presentationPaused: presentationPaused))
            |> map(Optional.init)
            |> `catch` { _ -> Signal<Api.Updates?, NoError> in
                return .single(nil)
            }
        }

        disposable.set((signal
        |> deliverOnMainQueue).start(next: { [weak self] updates in
            guard let strongSelf = self else {
                return
            }

            if let updates = updates {
                var stateUpdates: [GroupCallParticipantsContext.Update] = []

                loop: for update in updates.allUpdates {
                    switch update {
                    case let .updateGroupCallParticipants(call, participants, version):
                        switch call {
                        case let .inputGroupCall(updateCallId, _):
                            if updateCallId != id {
                                continue loop
                            }
                        case .inputGroupCallSlug, .inputGroupCallInviteMessage:
                            continue loop
                        }
                        stateUpdates.append(.state(update: GroupCallParticipantsContext.Update.StateUpdate(participants: participants, version: version, removePendingMuteStates: [peerId])))
                    default:
                        break
                    }
                }

                strongSelf.addUpdates(updates: stateUpdates)

                strongSelf.account.stateManager.addUpdates(updates)
            }
        }))
    }
    
    public func raiseHand() {
        self.updateMuteState(peerId: self.myPeerId, muteState: nil, volume: nil, raiseHand: true)
    }
    
    public func lowerHand() {
        self.updateMuteState(peerId: self.myPeerId, muteState: nil, volume: nil, raiseHand: false)
    }
    
    public func updateShouldBeRecording(_ shouldBeRecording: Bool, title: String?, videoOrientation: Bool?) {
        var flags: Int32 = 0
        if shouldBeRecording {
            flags |= 1 << 0
        }
        if let title = title, !title.isEmpty {
            flags |= (1 << 1)
        }
        var videoPortrait: Api.Bool?
        if let videoOrientation = videoOrientation {
            flags |= (1 << 2)
            videoPortrait = videoOrientation ? .boolTrue : .boolFalse
        }

        self.updateShouldBeRecordingDisposable.set((self.account.network.request(Api.functions.phone.toggleGroupCallRecord(flags: flags, call: self.reference.apiInputGroupCall, title: title, videoPortrait: videoPortrait))
        |> deliverOnMainQueue).start(next: { [weak self] updates in
            guard let strongSelf = self else {
                return
            }
            strongSelf.account.stateManager.addUpdates(updates)
        }))
    }
    
    public func updateDefaultParticipantsAreMuted(isMuted: Bool) {
        if isMuted == self.stateValue.state.defaultParticipantsAreMuted.isMuted {
            return
        }
        self.stateValue.state.defaultParticipantsAreMuted.isMuted = isMuted
        
        self.updateDefaultMuteDisposable.set((self.account.network.request(Api.functions.phone.toggleGroupCallSettings(flags: 1 << 0, call: self.reference.apiInputGroupCall, joinMuted: isMuted ? .boolTrue : .boolFalse))
        |> deliverOnMainQueue).start(next: { [weak self] updates in
            guard let strongSelf = self else {
                return
            }
            strongSelf.account.stateManager.addUpdates(updates)
        }))
    }
    
    public func resetInviteLinks() {
        self.resetInviteLinksDisposable.set((self.account.network.request(Api.functions.phone.toggleGroupCallSettings(flags: 1 << 1, call: self.reference.apiInputGroupCall, joinMuted: nil))
        |> deliverOnMainQueue).start(next: { [weak self] updates in
            guard let strongSelf = self else {
                return
            }
            strongSelf.account.stateManager.addUpdates(updates)
        }))
    }
    
    public func toggleScheduledSubscription(_ subscribe: Bool) {
        guard let peerId = self.peerId else {
            return
        }
        if subscribe == self.stateValue.state.subscribedToScheduled {
            return
        }
        self.stateValue.state.subscribedToScheduled = subscribe
        
        self.subscribeDisposable.set(_internal_toggleScheduledGroupCallSubscription(account: self.account, peerId: peerId, reference: self.reference, subscribe: subscribe).start())
    }
    
    public func loadMore(token: String) {
        if token != self.stateValue.state.nextParticipantsFetchOffset {
            Logger.shared.log("GroupCallParticipantsContext", "loadMore called with an invalid token \(token) (the valid one is \(String(describing: self.stateValue.state.nextParticipantsFetchOffset)))")
            return
        }
        if self.isLoadingMore {
            return
        }
        self.isLoadingMore = true
        
        self.disposable.set((_internal_getGroupCallParticipants(account: self.account, reference: self.reference, offset: token, ssrcs: [], limit: 100, sortAscending: self.stateValue.state.sortAscending)
        |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isLoadingMore = false
            
            var updatedState = strongSelf.stateValue.state
            
            updatedState.participants = mergeAndSortParticipants(current: updatedState.participants, with: state.participants, sortAscending: updatedState.sortAscending)
            
            updatedState.nextParticipantsFetchOffset = state.nextParticipantsFetchOffset
            updatedState.totalCount = max(updatedState.totalCount, state.totalCount)
            updatedState.version = max(updatedState.version, updatedState.version)
            
            strongSelf.stateValue.state = updatedState
            
            if strongSelf.shouldResetStateFromServer {
                strongSelf.resetStateFromServer()
            }
        }))
    }
}

extension GroupCallParticipantsContext.Update.StateUpdate.ParticipantUpdate {
    init(_ apiParticipant: Api.GroupCallParticipant) {
        switch apiParticipant {
        case let .groupCallParticipant(flags, apiPeerId, date, activeDate, source, volume, about, raiseHandRating, video, presentation):
            let peerId: PeerId = apiPeerId.peerId
            let ssrc = UInt32(bitPattern: source)
            let muted = (flags & (1 << 0)) != 0
            let mutedByYou = (flags & (1 << 9)) != 0
            var muteState: GroupCallParticipantsContext.Participant.MuteState?
            if muted {
                let canUnmute = (flags & (1 << 2)) != 0
                muteState = GroupCallParticipantsContext.Participant.MuteState(canUnmute: canUnmute, mutedByYou: mutedByYou)
            } else if mutedByYou {
                muteState = GroupCallParticipantsContext.Participant.MuteState(canUnmute: false, mutedByYou: mutedByYou)
            }
            let isRemoved = (flags & (1 << 1)) != 0
            let justJoined = (flags & (1 << 4)) != 0
            let joinedVideo = (flags & (1 << 15)) != 0
            let isMin = (flags & (1 << 8)) != 0
            
            let participationStatusChange: GroupCallParticipantsContext.Update.StateUpdate.ParticipantUpdate.ParticipationStatusChange
            if isRemoved {
                participationStatusChange = .left
            } else if justJoined {
                participationStatusChange = .joined
            } else {
                participationStatusChange = .none
            }
            
            var videoDescription = video.flatMap(GroupCallParticipantsContext.Participant.VideoDescription.init)
            var presentationDescription = presentation.flatMap(GroupCallParticipantsContext.Participant.VideoDescription.init)
            if muteState?.canUnmute == false {
                videoDescription = nil
                presentationDescription = nil
            }
            self.init(
                peerId: peerId,
                ssrc: ssrc,
                videoDescription: videoDescription,
                presentationDescription: presentationDescription,
                joinTimestamp: date,
                activityTimestamp: activeDate.flatMap(Double.init),
                raiseHandRating: raiseHandRating,
                muteState: muteState,
                participationStatusChange: participationStatusChange,
                volume: volume,
                about: about,
                joinedVideo: joinedVideo,
                isMin: isMin
            )
        }
    }
}

extension GroupCallParticipantsContext.Update.StateUpdate {
    init(participants: [Api.GroupCallParticipant], version: Int32, removePendingMuteStates: Set<PeerId> = Set()) {
        self.init(
            participantUpdates: participants.map { GroupCallParticipantsContext.Update.StateUpdate.ParticipantUpdate($0) },
            version: version,
            removePendingMuteStates: removePendingMuteStates
        )
    }
}

public enum InviteToGroupCallError {
    case generic
}

func _internal_inviteToGroupCall(account: Account, callId: Int64, accessHash: Int64, peerId: PeerId) -> Signal<Never, InviteToGroupCallError> {
    return account.postbox.transaction { transaction -> Peer? in
        return transaction.getPeer(peerId)
    }
    |> castError(InviteToGroupCallError.self)
    |> mapToSignal { user -> Signal<Never, InviteToGroupCallError> in
        guard let user = user else {
            return .fail(.generic)
        }
        guard let apiUser = apiInputUser(user) else {
            return .fail(.generic)
        }
        
        return account.network.request(Api.functions.phone.inviteToGroupCall(call: .inputGroupCall(id: callId, accessHash: accessHash), users: [apiUser]))
        |> mapError { _ -> InviteToGroupCallError in
            return .generic
        }
        |> mapToSignal { result -> Signal<Never, InviteToGroupCallError> in
            account.stateManager.addUpdates(result)
            
            return .complete()
        }
    }
}

public struct GroupCallInviteLinks {
    public let listenerLink: String
    public let speakerLink: String?
    
    public init(listenerLink: String, speakerLink: String?) {
        self.listenerLink = listenerLink
        self.speakerLink = speakerLink
    }
}

func _internal_groupCallInviteLinks(account: Account, reference: InternalGroupCallReference, isConference: Bool) -> Signal<GroupCallInviteLinks?, NoError> {
    let call = reference.apiInputGroupCall
    let listenerInvite: Signal<String?, NoError> = account.network.request(Api.functions.phone.exportGroupCallInvite(flags: 0, call: call))
    |> map(Optional.init)
    |> `catch` { _ -> Signal<Api.phone.ExportedGroupCallInvite?, NoError> in
        return .single(nil)
    }
    |> mapToSignal { result -> Signal<String?, NoError> in
        if let result = result,  case let .exportedGroupCallInvite(link) = result {
            return .single(link)
        }
        return .single(nil)
    }

    let speakerInvite: Signal<String?, NoError> = account.network.request(Api.functions.phone.exportGroupCallInvite(flags: 1 << 0, call: call))
    |> map(Optional.init)
    |> `catch` { _ -> Signal<Api.phone.ExportedGroupCallInvite?, NoError> in
        return .single(nil)
    }
    |> mapToSignal { result -> Signal<String?, NoError> in
        if let result = result,  case let .exportedGroupCallInvite(link) = result {
            return .single(link)
        }
        return .single(nil)
    }

    if isConference {
        return speakerInvite
        |> map { speakerLink -> GroupCallInviteLinks? in
            guard let speakerLink = speakerLink else {
                return nil
            }
            return GroupCallInviteLinks(listenerLink: speakerLink, speakerLink: speakerLink)
        }
    }
    
    return combineLatest(listenerInvite, speakerInvite)
    |> map { listenerLink, speakerLink in
    
        if let listenerLink = listenerLink {
            return GroupCallInviteLinks(listenerLink: listenerLink, speakerLink: speakerLink)
        } else {
            return nil
        }
    }
}

public enum EditGroupCallTitleError {
    case generic
}

func _internal_editGroupCallTitle(account: Account, callId: Int64, accessHash: Int64, title: String) -> Signal<Never, EditGroupCallTitleError> {
    return account.network.request(Api.functions.phone.editGroupCallTitle(call: .inputGroupCall(id: callId, accessHash: accessHash), title: title)) |> mapError { _ -> EditGroupCallTitleError in
        return .generic
    }
    |> mapToSignal { result -> Signal<Never, EditGroupCallTitleError> in
        account.stateManager.addUpdates(result)
        return .complete()
    }
}

func _internal_groupCallDisplayAsAvailablePeers(accountPeerId: PeerId, network: Network, postbox: Postbox, peerId: PeerId) -> Signal<[FoundPeer], NoError> {
    return postbox.transaction { transaction -> Api.InputPeer? in
        return transaction.getPeer(peerId).flatMap(apiInputPeer)
    }
    |> mapToSignal { inputPeer in
        guard let inputPeer = inputPeer else {
            return .complete()
        }
        return network.request(Api.functions.phone.getGroupCallJoinAs(peer: inputPeer))
        |> map(Optional.init)
        |> `catch` { _ -> Signal<Api.phone.JoinAsPeers?, NoError> in
            return .single(nil)
        }
        |> mapToSignal { result -> Signal<[FoundPeer], NoError> in
            guard let result = result else {
                return .single([])
            }
            switch result {
            case let .joinAsPeers(_, chats, users):
                return postbox.transaction { transaction -> [FoundPeer] in
                    var subscribers: [PeerId: Int32] = [:]
                    let parsedPeers = AccumulatedPeers(transaction: transaction, chats: chats, users: users)
                    for chat in chats {
                        if let groupOrChannel = parseTelegramGroupOrChannel(chat: chat) {
                            switch chat {
                            case let .channel(_, _, _, _, _, _, _, _, _, _, _, _, participantsCount, _, _, _, _, _, _, _, _, _, _):
                                if let participantsCount = participantsCount {
                                    subscribers[groupOrChannel.id] = participantsCount
                                }
                            case let .chat(_, _, _, _, participantsCount, _, _, _, _, _):
                                subscribers[groupOrChannel.id] = participantsCount
                            default:
                                break
                            }
                        }
                    }
                    
                    updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: parsedPeers)
                    
                    var peers: [Peer] = []
                    for chat in chats {
                        if let peer = transaction.getPeer(chat.peerId) {
                            peers.append(peer)
                        }
                    }
                    
                    return peers.map { FoundPeer(peer: $0, subscribers: subscribers[$0.id]) }
                }
            }
        }
        
    }
}

public final class CachedDisplayAsPeers: Codable {
    public let peerIds: [PeerId]
    public let timestamp: Int32
    
    public init(peerIds: [PeerId], timestamp: Int32) {
        self.peerIds = peerIds
        self.timestamp = timestamp
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.peerIds = (try container.decode([Int64].self, forKey: "peerIds")).map(PeerId.init)
        self.timestamp = try container.decode(Int32.self, forKey: "timestamp")
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode(self.peerIds.map { $0.toInt64() }, forKey: "peerIds")
        try container.encode(self.timestamp, forKey: "timestamp")
    }
}

func _internal_clearCachedGroupCallDisplayAsAvailablePeers(account: Account, peerId: PeerId) -> Signal<Never, NoError> {
    return account.postbox.transaction { transaction -> Void in
        let key = ValueBoxKey(length: 8)
        key.setInt64(0, value: peerId.toInt64())
        transaction.removeItemCacheEntry(id: ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.cachedGroupCallDisplayAsPeers, key: key))
    }
    |> ignoreValues
}

func _internal_cachedGroupCallDisplayAsAvailablePeers(account: Account, peerId: PeerId) -> Signal<[FoundPeer], NoError> {
    let key = ValueBoxKey(length: 8)
    key.setInt64(0, value: peerId.toInt64())
    return account.postbox.transaction { transaction -> ([FoundPeer], Int32)? in
        let cached = transaction.retrieveItemCacheEntry(id: ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.cachedGroupCallDisplayAsPeers, key: key))?.get(CachedDisplayAsPeers.self)
        if let cached = cached {
            var peers: [FoundPeer] = []
            for peerId in cached.peerIds {
                if let peer = transaction.getPeer(peerId) {
                    var subscribers: Int32?
                    if let cachedData = transaction.getPeerCachedData(peerId: peerId) as? CachedChannelData {
                        subscribers = cachedData.participantsSummary.memberCount
                    }
                    peers.append(FoundPeer(peer: peer, subscribers: subscribers))
                }
            }
            return (peers, cached.timestamp)
        } else {
            return nil
        }
    }
    |> mapToSignal { cachedPeersAndTimestamp -> Signal<[FoundPeer], NoError> in
        let currentTimestamp = Int32(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970)
        if let (cachedPeers, timestamp) = cachedPeersAndTimestamp, currentTimestamp - timestamp < 60 * 3 && !cachedPeers.isEmpty {
            return .single(cachedPeers)
        } else {
            return _internal_groupCallDisplayAsAvailablePeers(accountPeerId: account.peerId, network: account.network, postbox: account.postbox, peerId: peerId)
            |> mapToSignal { peers -> Signal<[FoundPeer], NoError> in
                return account.postbox.transaction { transaction -> [FoundPeer] in
                    let currentTimestamp = Int32(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970)
                    if let entry = CodableEntry(CachedDisplayAsPeers(peerIds: peers.map { $0.peer.id }, timestamp: currentTimestamp)) {
                        transaction.putItemCacheEntry(id: ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.cachedGroupCallDisplayAsPeers, key: key), entry: entry)
                    }
                    return peers
                }
            }
        }
    }
}

func _internal_updatedCurrentPeerGroupCall(postbox: Postbox, network: Network, accountPeerId: PeerId, peerId: PeerId) -> Signal<CachedChannelData.ActiveCall?, NoError> {
    return _internal_fetchAndUpdateCachedPeerData(accountPeerId: accountPeerId, peerId: peerId, network: network, postbox: postbox)
    |> mapToSignal { _ -> Signal<CachedChannelData.ActiveCall?, NoError> in
        return postbox.transaction { transaction -> CachedChannelData.ActiveCall? in
            return (transaction.getPeerCachedData(peerId: peerId) as? CachedChannelData)?.activeCall
        }
    }
}

private func mergeAndSortParticipants(current currentParticipants: [GroupCallParticipantsContext.Participant], with updatedParticipants: [GroupCallParticipantsContext.Participant], sortAscending: Bool) -> [GroupCallParticipantsContext.Participant] {
    var mergedParticipants = currentParticipants
    
    var existingParticipantIndices: [GroupCallParticipantsContext.Participant.Id: Int] = [:]
    for i in 0 ..< mergedParticipants.count {
        existingParticipantIndices[mergedParticipants[i].id] = i
    }
    for participant in updatedParticipants {
        if let _ = existingParticipantIndices[participant.id] {
        } else {
            existingParticipantIndices[participant.id] = mergedParticipants.count
            mergedParticipants.append(participant)
        }
    }

    mergedParticipants.sort(by: { GroupCallParticipantsContext.Participant.compare(lhs: $0, rhs: $1, sortAscending: sortAscending) })
    
    return mergedParticipants
}

public final class AudioBroadcastDataSource {
    let download: Download
    
    fileprivate init(download: Download) {
        self.download = download
    }
}

func _internal_getAudioBroadcastDataSource(account: Account, callId: Int64, accessHash: Int64) -> Signal<AudioBroadcastDataSource?, NoError> {
    return account.network.request(Api.functions.phone.getGroupCall(call: .inputGroupCall(id: callId, accessHash: accessHash), limit: 4))
    |> map(Optional.init)
    |> `catch` { _ -> Signal<Api.phone.GroupCall?, NoError> in
        return .single(nil)
    }
    |> mapToSignal { result -> Signal<AudioBroadcastDataSource?, NoError> in
        guard let result = result else {
            return .single(nil)
        }
        switch result {
        case let .groupCall(call, _, _, _, _):
            if let datacenterId = GroupCallInfo(call)?.streamDcId.flatMap(Int.init) {
                return account.network.download(datacenterId: datacenterId, isMedia: true, tag: nil)
                |> map { download -> AudioBroadcastDataSource? in
                    return AudioBroadcastDataSource(download: download)
                }
            } else {
                return .single(nil)
            }
        }
    }
}

public struct GetAudioBroadcastPartResult {
    public enum Status {
        case data(Data)
        case notReady
        case resyncNeeded
        case rejoinNeeded
    }
    
    public var status: Status
    public var responseTimestamp: Double

    public init(status: Status, responseTimestamp: Double) {
        self.status = status
        self.responseTimestamp = responseTimestamp
    }
}

func _internal_getAudioBroadcastPart(dataSource: AudioBroadcastDataSource, callId: Int64, accessHash: Int64, timestampIdMilliseconds: Int64, durationMilliseconds: Int64) -> Signal<GetAudioBroadcastPartResult, NoError> {
    let scale: Int32
    switch durationMilliseconds {
    case 1000:
        scale = 0
    case 500:
        scale = 1
    default:
        return .single(GetAudioBroadcastPartResult(status: .notReady, responseTimestamp: Double(timestampIdMilliseconds) / 1000.0))
    }
    
    return dataSource.download.requestWithAdditionalData(Api.functions.upload.getFile(flags: 0, location: .inputGroupCallStream(flags: 0, call: .inputGroupCall(id: callId, accessHash: accessHash), timeMs: timestampIdMilliseconds, scale: scale, videoChannel: nil, videoQuality: nil), offset: 0, limit: 128 * 1024), automaticFloodWait: false, failOnServerErrors: true)
    |> map { result, responseTimestamp -> GetAudioBroadcastPartResult in
        switch result {
        case let .file(_, _, bytes):
            return GetAudioBroadcastPartResult(
                status: .data(bytes.makeData()),
                responseTimestamp: responseTimestamp
            )
        case .fileCdnRedirect:
            return GetAudioBroadcastPartResult(
                status: .notReady,
                responseTimestamp: responseTimestamp
            )
        }
    }
    |> `catch` { error, responseTimestamp -> Signal<GetAudioBroadcastPartResult, NoError> in
        if error.errorDescription == "GROUPCALL_JOIN_MISSING" {
            return .single(GetAudioBroadcastPartResult(
                status: .rejoinNeeded,
                responseTimestamp: responseTimestamp
            ))
        } else if error.errorDescription.hasPrefix("FLOOD_WAIT") || error.errorDescription == "TIME_TOO_BIG" {
            return .single(GetAudioBroadcastPartResult(
                status: .notReady,
                responseTimestamp: responseTimestamp
            ))
        } else if error.errorDescription == "TIME_INVALID" || error.errorDescription == "TIME_TOO_SMALL" {
            return .single(GetAudioBroadcastPartResult(
                status: .resyncNeeded,
                responseTimestamp: responseTimestamp
            ))
        } else {
            return .single(GetAudioBroadcastPartResult(
                status: .resyncNeeded,
                responseTimestamp: responseTimestamp
            ))
        }
    }
}

func _internal_getVideoBroadcastPart(dataSource: AudioBroadcastDataSource, callId: Int64, accessHash: Int64, timestampIdMilliseconds: Int64, durationMilliseconds: Int64, channelId: Int32, quality: Int32) -> Signal<GetAudioBroadcastPartResult, NoError> {
    let scale: Int32
    switch durationMilliseconds {
    case 1000:
        scale = 0
    case 500:
        scale = 1
    case 32000:
        scale = -5
    default:
        return .single(GetAudioBroadcastPartResult(status: .notReady, responseTimestamp: Double(timestampIdMilliseconds) / 1000.0))
    }

    return dataSource.download.requestWithAdditionalData(Api.functions.upload.getFile(flags: 0, location: .inputGroupCallStream(flags: 1 << 0, call: .inputGroupCall(id: callId, accessHash: accessHash), timeMs: timestampIdMilliseconds, scale: scale, videoChannel: channelId, videoQuality: quality), offset: 0, limit: 512 * 1024), automaticFloodWait: false, failOnServerErrors: true)
    |> map { result, responseTimestamp -> GetAudioBroadcastPartResult in
        switch result {
        case let .file(_, _, bytes):
            return GetAudioBroadcastPartResult(
                status: .data(bytes.makeData()),
                responseTimestamp: responseTimestamp
            )
        case .fileCdnRedirect:
            return GetAudioBroadcastPartResult(
                status: .notReady,
                responseTimestamp: responseTimestamp
            )
        }
    }
    |> `catch` { error, responseTimestamp -> Signal<GetAudioBroadcastPartResult, NoError> in
        if error.errorDescription == "GROUPCALL_JOIN_MISSING" {
            return .single(GetAudioBroadcastPartResult(
                status: .rejoinNeeded,
                responseTimestamp: responseTimestamp
            ))
        } else if error.errorDescription.hasPrefix("FLOOD_WAIT") || error.errorDescription == "TIME_TOO_BIG" {
            return .single(GetAudioBroadcastPartResult(
                status: .notReady,
                responseTimestamp: responseTimestamp
            ))
        } else if error.errorDescription == "TIME_INVALID" || error.errorDescription == "TIME_TOO_SMALL" || error.errorDescription.hasSuffix("_CHANNEL_INVALID") {
            return .single(GetAudioBroadcastPartResult(
                status: .resyncNeeded,
                responseTimestamp: responseTimestamp
            ))
        } else {
            return .single(GetAudioBroadcastPartResult(
                status: .resyncNeeded,
                responseTimestamp: responseTimestamp
            ))
        }
    }
}

extension GroupCallParticipantsContext.Participant {
     init?(_ apiParticipant: Api.GroupCallParticipant, transaction: Transaction) {
        switch apiParticipant {
            case let .groupCallParticipant(flags, apiPeerId, date, activeDate, source, volume, about, raiseHandRating, video, presentation):
                let peerId: PeerId = apiPeerId.peerId
                let ssrc = UInt32(bitPattern: source)
                guard let peer = transaction.getPeer(peerId) else {
                    return nil
                }
                let muted = (flags & (1 << 0)) != 0
                let mutedByYou = (flags & (1 << 9)) != 0
                var muteState: GroupCallParticipantsContext.Participant.MuteState?
                if muted {
                    let canUnmute = (flags & (1 << 2)) != 0
                    muteState = GroupCallParticipantsContext.Participant.MuteState(canUnmute: canUnmute, mutedByYou: mutedByYou)
                } else if mutedByYou {
                    muteState = GroupCallParticipantsContext.Participant.MuteState(canUnmute: false, mutedByYou: mutedByYou)
                }
                 
                var videoDescription = video.flatMap(GroupCallParticipantsContext.Participant.VideoDescription.init)
                var presentationDescription = presentation.flatMap(GroupCallParticipantsContext.Participant.VideoDescription.init)
                if muteState?.canUnmute == false {
                    videoDescription = nil
                    presentationDescription = nil
                }
                let joinedVideo = (flags & (1 << 15)) != 0
                
                self.init(
                    id: .peer(peer.id),
                    peer: EnginePeer(peer),
                    ssrc: ssrc,
                    videoDescription: videoDescription,
                    presentationDescription: presentationDescription,
                    joinTimestamp: date,
                    raiseHandRating: raiseHandRating,
                    hasRaiseHand: raiseHandRating != nil,
                    activityTimestamp: activeDate.flatMap(Double.init),
                    activityRank: nil,
                    muteState: muteState,
                    volume: volume,
                    about: about,
                    joinedVideo: joinedVideo
                )
        }
    }
}

private extension GroupCallParticipantsContext.Participant.VideoDescription {
    init(_ apiVideo: Api.GroupCallParticipantVideo) {
        switch apiVideo {
        case let .groupCallParticipantVideo(flags, endpoint, sourceGroups, audioSource):
            var parsedSsrcGroups: [SsrcGroup] = []
            for group in sourceGroups {
                switch group {
                case let .groupCallParticipantVideoSourceGroup(semantics, sources):
                    parsedSsrcGroups.append(SsrcGroup(semantics: semantics, ssrcs: sources.map(UInt32.init(bitPattern:))))
                }
            }
            let isPaused = (flags & (1 << 0)) != 0
            self.init(endpointId: endpoint, ssrcGroups: parsedSsrcGroups, audioSsrc: audioSource.flatMap(UInt32.init(bitPattern:)), isPaused: isPaused)
        }
    }
}

public struct GroupCallStreamCredentials : Equatable {
    public var url: String
    public var streamKey: String
}

public enum GetGroupCallStreamCredentialsError {
    case generic
}

func _internal_getGroupCallStreamCredentials(account: Account, peerId: PeerId, revokePreviousCredentials: Bool) -> Signal<GroupCallStreamCredentials, GetGroupCallStreamCredentialsError> {
    return account.postbox.transaction { transaction -> Api.InputPeer? in
        return transaction.getPeer(peerId).flatMap(apiInputPeer)
    }
    |> castError(GetGroupCallStreamCredentialsError.self)
    |> mapToSignal { inputPeer -> Signal<GroupCallStreamCredentials, GetGroupCallStreamCredentialsError> in
        guard let inputPeer = inputPeer else {
            return .fail(.generic)
        }
        
        return account.network.request(Api.functions.phone.getGroupCallStreamRtmpUrl(peer: inputPeer, revoke: revokePreviousCredentials ? .boolTrue : .boolFalse))
        |> mapError { _ -> GetGroupCallStreamCredentialsError in
            return .generic
        }
        |> map { result -> GroupCallStreamCredentials in
            switch result {
            case let .groupCallStreamRtmpUrl(url, key):
                return GroupCallStreamCredentials(url: url, streamKey: key)
            }
        }
    }
}

public enum CreateConferenceCallError {
    case generic
}

public final class EngineCreatedGroupCall {
    public let slug: String
    public let link: String
    public let callInfo: GroupCallInfo

    public init(slug: String, link: String, callInfo: GroupCallInfo) {
        self.slug = slug
        self.link = link
        self.callInfo = callInfo
    }
}

func _internal_createConferenceCall(postbox: Postbox, network: Network, accountPeerId: PeerId) -> Signal<EngineCreatedGroupCall, CreateConferenceCallError> {
    return network.request(Api.functions.phone.createConferenceCall(flags: 0, randomId: Int32.random(in: Int32.min ... Int32.max), publicKey: nil, block: nil, params: nil))
    |> mapError { _ -> CreateConferenceCallError in
        return .generic
    }
    |> mapToSignal { result in
        for update in result.allUpdates {
            if case let .updateGroupCall(_, _, call) = update {
                return postbox.transaction { transaction -> Signal<EngineCreatedGroupCall, CreateConferenceCallError> in
                    guard let info = GroupCallInfo(call) else {
                        return .fail(.generic)
                    }
                    
                    let parsedPeers = AccumulatedPeers(transaction: transaction, chats: result.chats, users: result.users)
                    
                    updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: parsedPeers)
                    
                    let speakerInvite: Signal<EngineCreatedGroupCall, CreateConferenceCallError> = network.request(Api.functions.phone.exportGroupCallInvite(flags: 1 << 0, call: .inputGroupCall(id: info.id, accessHash: info.accessHash)))
                    |> map(Optional.init)
                    |> `catch` { _ -> Signal<Api.phone.ExportedGroupCallInvite?, NoError> in
                        return .single(nil)
                    }
                    |> castError(CreateConferenceCallError.self)
                    |> mapToSignal { result -> Signal<EngineCreatedGroupCall, CreateConferenceCallError> in
                        if let result, case let .exportedGroupCallInvite(link) = result {
                            let slug = link.components(separatedBy: "/").last ?? link
                            return .single(EngineCreatedGroupCall(
                                slug: slug,
                                link: link,
                                callInfo: info
                            ))
                        }
                        return .fail(.generic)
                    }
                    return speakerInvite
                }
                |> mapError { _ -> CreateConferenceCallError in
                }
                |> switchToLatest
            }
        }
        
        return .fail(.generic)
    }
}

public enum RevokeConferenceInviteLinkError {
    case generic
}

func _internal_revokeConferenceInviteLink(account: Account, reference: InternalGroupCallReference, link: String) -> Signal<GroupCallInviteLinks, RevokeConferenceInviteLinkError> {
    return account.network.request(Api.functions.phone.toggleGroupCallSettings(flags: 1 << 1, call: reference.apiInputGroupCall, joinMuted: .boolFalse))
    |> mapError { _ -> RevokeConferenceInviteLinkError in
        return .generic
    }
    |> mapToSignal { result -> Signal<GroupCallInviteLinks, RevokeConferenceInviteLinkError> in
        account.stateManager.addUpdates(result)

        return _internal_groupCallInviteLinks(account: account, reference: reference, isConference: true)
        |> castError(RevokeConferenceInviteLinkError.self)
        |> mapToSignal { result -> Signal<GroupCallInviteLinks, RevokeConferenceInviteLinkError> in
            guard let result = result else {
                return .fail(.generic)
            }
            return .single(result)
        }
    }
}

public enum ConfirmAddConferenceParticipantError {
    case generic
}

func _internal_pollConferenceCallBlockchain(network: Network, reference: InternalGroupCallReference, subChainId: Int, offset: Int, limit: Int) -> Signal<(blocks: [Data], nextOffset: Int)?, NoError> {
    return network.request(Api.functions.phone.getGroupCallChainBlocks(call: reference.apiInputGroupCall, subChainId: Int32(subChainId), offset: Int32(offset), limit: Int32(limit)))
    |> map(Optional.init)
    |> `catch` { error -> Signal<Api.Updates?, NoError> in
        return .single(nil)
    }
    |> map { result -> (blocks: [Data], nextOffset: Int)? in
        guard let result = result else {
            return nil
        }
        var blocks: [Data] = []
        var nextOffset: Int?
        for update in result.allUpdates {
            switch update {
            case let .updateGroupCallChainBlocks(_, updateSubChainId, updateBlocks, updateNextOffset):
                if updateSubChainId == Int32(subChainId) {
                    blocks.append(contentsOf: updateBlocks.map { $0.makeData() })
                    nextOffset = Int(updateNextOffset)
                }
            default:
                break
            }
        }
        guard let nextOffset = nextOffset else {
            return nil
        }
        return (blocks: blocks, nextOffset: nextOffset)
    }
}

func _internal_sendConferenceCallBroadcast(account: Account, callId: Int64, accessHash: Int64, block: Data) -> Signal<Never, NoError> {
    return account.network.request(Api.functions.phone.sendConferenceCallBroadcast(call: .inputGroupCall(id: callId, accessHash: accessHash), block: Buffer(data: block)))
    |> retry(retryOnError: { _ in
        return true
    }, delayIncrement: 0.1, maxDelay: 1.0, maxRetries: 5, onQueue: Queue.concurrentDefaultQueue())
    |> map(Optional.init)
    |> `catch` { error -> Signal<Api.Updates?, NoError> in
        return .single(nil)
    }
    |> mapToSignal { result -> Signal<Never, NoError> in
        guard let result = result else {
            return .complete()
        }
        account.stateManager.addUpdates(result)

        return .complete()
    }
}

func _internal_refreshInlineGroupCall(account: Account, messageId: MessageId) -> Signal<Never, NoError> {
    return _internal_getCurrentGroupCallInfo(account: account, reference: .message(id: messageId))
    |> mapToSignal { result -> Signal<Never, NoError> in
        return account.postbox.transaction { transaction -> Void in
            transaction.updateMessage(messageId, update: { currentMessage in
                var storeForwardInfo: StoreMessageForwardInfo?
                if let forwardInfo = currentMessage.forwardInfo {
                    storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
                }
                var updatedMedia = currentMessage.media

                for i in 0 ..< updatedMedia.count {
                    if let action = updatedMedia[i] as? TelegramMediaAction, case let .conferenceCall(conferenceCall) = action.action {
                        let otherParticipants: [PeerId] = conferenceCall.otherParticipants
                        var duration: Int32? = conferenceCall.duration
                        if let result {
                            duration = result.duration
                        } else {
                            duration = nil
                        }
                        
                        updatedMedia[i] = TelegramMediaAction(action: .conferenceCall(TelegramMediaActionType.ConferenceCall(
                            callId: conferenceCall.callId,
                            duration: duration,
                            flags: conferenceCall.flags,
                            otherParticipants: otherParticipants
                        )))
                    }
                }
                return .update(StoreMessage(
                    id: currentMessage.id,
                    globallyUniqueId: currentMessage.globallyUniqueId,
                    groupingKey: currentMessage.groupingKey,
                    threadId: currentMessage.threadId,
                    timestamp: currentMessage.timestamp,
                    flags: StoreMessageFlags(currentMessage.flags),
                    tags: currentMessage.tags,
                    globalTags: currentMessage.globalTags,
                    localTags: currentMessage.localTags,
                    forwardInfo: storeForwardInfo,
                    authorId: currentMessage.author?.id,
                    text: currentMessage.text,
                    attributes: currentMessage.attributes,
                    media: updatedMedia
                ))
            })
        }
        |> ignoreValues
    }
}
