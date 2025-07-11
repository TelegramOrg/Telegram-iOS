import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramCore
import SwiftSignalKit
import Postbox
import TelegramPresentationData
import AccountContext
import ContextUI
import PhotoResources
import TelegramUIPreferences
import ItemListPeerItem
import ItemListPeerActionItem
import MergeLists
import ItemListUI
import PeerInfoVisualMediaPaneNode
import PeerInfoPaneNode
import ContactsPeerItem

private struct PeerMembersListTransaction {
    let deletions: [ListViewDeleteItem]
    let insertions: [ListViewInsertItem]
    let updates: [ListViewUpdateItem]
    let animated: Bool
}

enum PeerMembersListAction {
    case open
    case promote
    case restrict
    case remove
    case openStories(sourceView: UIView)
}

private enum PeerMembersListEntryStableId: Hashable {
    case addMember
    case peer(PeerId)
}

private enum PeerMembersListEntry: Comparable, Identifiable {
    case addMember(PresentationTheme, String)
    case member(theme: PresentationTheme, index: Int, member: PeerInfoMember)
        
    var stableId: PeerMembersListEntryStableId {
        switch self {
            case .addMember:
                return .addMember
            case let .member(_, _, member):
                return .peer(member.id)
        }
    }
    
    static func ==(lhs: PeerMembersListEntry, rhs: PeerMembersListEntry) -> Bool {
        switch lhs {
            case let .addMember(lhsTheme, lhsText):
                if case let .addMember(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .member(lhsTheme, lhsIndex, lhsMember):
                if case let .member(rhsTheme, rhsIndex, rhsMember) = rhs, lhsTheme === rhsTheme, lhsIndex == rhsIndex, lhsMember == rhsMember {
                    return true
                } else {
                    return false
                }
        }
    }
    
    static func <(lhs: PeerMembersListEntry, rhs: PeerMembersListEntry) -> Bool {
        switch lhs {
            case .addMember:
                switch rhs {
                    case .addMember:
                        return false
                    case .member:
                        return true
                }
            case let .member(_, lhsIndex, _):
                switch rhs {
                    case .addMember:
                        return false
                    case let .member(_, rhsIndex, _):
                        return lhsIndex < rhsIndex
                }
        }
    }
    
    func item(context: AccountContext, presentationData: PresentationData, enclosingPeer: Peer, addMemberAction: @escaping () -> Void, action: @escaping (PeerInfoMember, PeerMembersListAction) -> Void, contextAction: ((PeerInfoMember, ASDisplayNode, ContextGesture?) -> Void)?) -> ListViewItem {
        switch self {
            case let .addMember(_, text):
                return ItemListPeerActionItem(presentationData: ItemListPresentationData(presentationData), icon: PresentationResourcesItemList.addPersonIcon(presentationData.theme), title: text, alwaysPlain: true, sectionId: 0, height: .compactPeerList, color: .accent, editing: false, action: {
                    addMemberAction()
                })
            case let .member(_, _, member):
                let label: String?
                if let rank = member.rank {
                    label = rank
                } else {
                    switch member.role {
                    case .creator:
                        label = presentationData.strings.GroupInfo_LabelOwner
                    case .admin:
                        label = presentationData.strings.GroupInfo_LabelAdmin
                    case .member:
                        label = nil
                    }
                }
                
                let actions = availableActionsForMemberOfPeer(accountPeerId: context.account.peerId, peer: enclosingPeer, member: member)
                
                var options: [ItemListPeerItemRevealOption] = []
                if actions.contains(.promote) && enclosingPeer is TelegramChannel{
                    options.append(ItemListPeerItemRevealOption(type: .neutral, title: presentationData.strings.GroupInfo_ActionPromote, action: {
                        action(member, .promote)
                    }))
                }
                if actions.contains(.restrict) {
                    if enclosingPeer is TelegramChannel {
                        options.append(ItemListPeerItemRevealOption(type: .warning, title: presentationData.strings.GroupInfo_ActionRestrict, action: {
                            action(member, .restrict)
                        }))
                    }
                    options.append(ItemListPeerItemRevealOption(type: .destructive, title: presentationData.strings.Common_Delete, action: {
                        action(member, .remove)
                    }))
                }
            
                let presence: EnginePeer.Presence
                if member.peer.id == context.account.peerId {
                    presence = EnginePeer.Presence(status: .present(until: Int32.max), lastActivity: 0)
                } else if let value = member.presence {
                    presence = EnginePeer.Presence(value)
                } else {
                    presence = EnginePeer.Presence(status: .longTimeAgo, lastActivity: 0)
                }
            
                return ContactsPeerItem(
                    presentationData: ItemListPresentationData(presentationData),
                    style: .plain,
                    sectionId: 0,
                    sortOrder: presentationData.nameSortOrder,
                    displayOrder: presentationData.nameDisplayOrder,
                    context: context,
                    peerMode: .memberList,
                    peer: .peer(peer: EnginePeer(member.peer), chatPeer: EnginePeer(member.peer)),
                    status: .presence(presence, presentationData.dateTimeFormat),
                    rightLabelText: label,
                    enabled: true,
                    selection: .none,
                    editing: ContactsPeerItemEditing(editable: false, editing: false, revealed: false),
                    options: options,
                    additionalActions: [],
                    actionIcon: .none,
                    index: nil,
                    header: nil,
                    action: member.peer.id == context.account.peerId ? nil : { _ in
                        action(member, .open)
                    },
                    disabledAction: nil,
                    setPeerIdWithRevealedOptions: { _, _ in
                    },
                    deletePeer: nil,
                    itemHighlighting: nil,
                    contextAction: contextAction == nil ? nil : { node, gesture, _ in
                        contextAction?(member, node, gesture)
                    },
                    animationCache: context.animationCache,
                    animationRenderer: context.animationRenderer,
                    storyStats: member.storyStats.flatMap { storyStats in
                        return (
                            total: storyStats.totalCount,
                            unseen: storyStats.unseenCount,
                            hasUnseenCloseFriends: storyStats.hasUnseenCloseFriends
                        )
                    },
                    openStories: { _, sourceNode in
                        action(member, .openStories(sourceView: sourceNode.view))
                    }
                )
                
                /*return ItemListPeerItem(
                    presentationData: ItemListPresentationData(presentationData),
                    dateTimeFormat: presentationData.dateTimeFormat,
                    nameDisplayOrder: presentationData.nameDisplayOrder,
                    context: context,
                    peer: EnginePeer(member.peer),
                    presence: member.presence.flatMap(EnginePeer.Presence.init),
                    text: .presence,
                    label: label == nil ? .none : .text(label!, .standard),
                    editing: ItemListPeerItemEditing(editable: !options.isEmpty, editing: false, revealed: false),
                    revealOptions: ItemListPeerItemRevealOptions(options: options),
                    switchValue: nil,
                    enabled: true, 
                    selectable: member.id != context.account.peerId,
                    sectionId: 0,
                    action: {
                        action(member, .open)
                    },
                    setPeerIdWithRevealedOptions: { _, _ in
                    },
                    removePeer: { _ in
                    },
                    contextAction: contextAction == nil ? nil : { node, gesture in
                        contextAction?(member, node, gesture)
                    },
                    hasTopStripe: false,
                    noInsets: true,
                    noCorners: true,
                    disableInteractiveTransitionIfNecessary: true,
                    storyStats: member.storyStats,
                    openStories: { sourceView in
                        action(member, .openStories(sourceView: sourceView))
                    }
                )*/
        }
    }
}

private func preparedTransition(from fromEntries: [PeerMembersListEntry], to toEntries: [PeerMembersListEntry], context: AccountContext, presentationData: PresentationData, enclosingPeer: Peer, addMemberAction: @escaping () -> Void, action: @escaping (PeerInfoMember, PeerMembersListAction) -> Void, contextAction: ((PeerInfoMember, ASDisplayNode, ContextGesture?) -> Void)?) -> PeerMembersListTransaction {
    let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: fromEntries, rightList: toEntries)
    
    let deletions = deleteIndices.map { ListViewDeleteItem(index: $0, directionHint: nil) }
    let insertions = indicesAndItems.map { ListViewInsertItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(context: context, presentationData: presentationData, enclosingPeer: enclosingPeer, addMemberAction: addMemberAction, action: action, contextAction: contextAction), directionHint: nil) }
    let updates = updateIndices.map { ListViewUpdateItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(context: context, presentationData: presentationData, enclosingPeer: enclosingPeer, addMemberAction: addMemberAction, action: action, contextAction: contextAction), directionHint: nil) }
    
    return PeerMembersListTransaction(deletions: deletions, insertions: insertions, updates: updates, animated: toEntries.count < fromEntries.count)
}

final class PeerInfoMembersPaneNode: ASDisplayNode, PeerInfoPaneNode {
    private let context: AccountContext
    private let membersContext: PeerInfoMembersContext
    private let addMemberAction: () -> Void
    private let action: (PeerInfoMember, PeerMembersListAction) -> Void
    
    weak var parentController: ViewController?
    
    private let listNode: ListView
    private var currentEntries: [PeerMembersListEntry] = []
    private var enclosingPeer: Peer?
    private var currentState: PeerInfoMembersState?
    private var canLoadMore: Bool = false
    private var enqueuedTransactions: [PeerMembersListTransaction] = []
    
    private var currentParams: (size: CGSize, isScrollingLockedAtTop: Bool)?
    private let presentationDataPromise = Promise<PresentationData>()
    
    private let ready = Promise<Bool>()
    private var didSetReady: Bool = false
    var isReady: Signal<Bool, NoError> {
        return self.ready.get()
    }

    var status: Signal<PeerInfoStatusData?, NoError> {
        return .single(nil)
    }

    var tabBarOffsetUpdated: ((ContainedViewLayoutTransition) -> Void)?
    var tabBarOffset: CGFloat {
        return 0.0
    }
        
    private var disposable: Disposable?
    
    init(context: AccountContext, peerId: PeerId, membersContext: PeerInfoMembersContext, addMemberAction: @escaping () -> Void, action: @escaping (PeerInfoMember, PeerMembersListAction) -> Void) {
        self.context = context
        self.membersContext = membersContext
        self.addMemberAction = addMemberAction
        self.action = action
        
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.listNode = ListView()
        self.listNode.accessibilityPageScrolledString = { row, count in
            return presentationData.strings.VoiceOver_ScrollStatus(row, count).string
        }
        
        super.init()
        
        self.listNode.preloadPages = true
        self.addSubnode(self.listNode)
        
        self.disposable = (combineLatest(queue: .mainQueue(),
            membersContext.state,
            self.presentationDataPromise.get(),
            context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        )
        |> deliverOnMainQueue).startStrict(next: { [weak self] state, presentationData, enclosingPeer in
            guard let strongSelf = self, let enclosingPeer = enclosingPeer else {
                return
            }
            
            strongSelf.enclosingPeer = enclosingPeer._asPeer()
            strongSelf.currentState = state
            strongSelf.updateState(enclosingPeer: enclosingPeer._asPeer(), state: state, presentationData: presentationData)
        })
        
        self.listNode.visibleBottomContentOffsetChanged = { [weak self] offset in
            guard let strongSelf = self, let state = strongSelf.currentState, case .ready(true) = state.dataState else {
                return
            }
            if case let .known(value) = offset, value < 100.0 {
                strongSelf.membersContext.loadMore()
            }
        }
    }
    
    deinit {
        self.disposable?.dispose()
    }
    
    func ensureMessageIsVisible(id: MessageId) {   
    }
    
    func scrollToTop() -> Bool {
        if !self.listNode.scrollToOffsetFromTop(0.0, animated: true) {
            self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: ListViewScrollToItem(index: 0, position: .top(0.0), animated: true, curve: .Default(duration: nil), directionHint: .Up), updateSizeAndInsets: nil, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
            return true
        } else {
            return false
        }
    }
    
    func update(size: CGSize, topInset: CGFloat, sideInset: CGFloat, bottomInset: CGFloat, deviceMetrics: DeviceMetrics, visibleHeight: CGFloat, isScrollingLockedAtTop: Bool, expandProgress: CGFloat, navigationHeight: CGFloat, presentationData: PresentationData, synchronous: Bool, transition: ContainedViewLayoutTransition) {
        let isFirstLayout = self.currentParams == nil
        self.currentParams = (size, isScrollingLockedAtTop)
        self.presentationDataPromise.set(.single(presentationData))
        
        transition.updateFrame(node: self.listNode, frame: CGRect(origin: CGPoint(), size: size))
        let (duration, curve) = listViewAnimationDurationAndCurve(transition: transition)

        var scrollToItem: ListViewScrollToItem?
        if isScrollingLockedAtTop {
            switch self.listNode.visibleContentOffset() {
            case let .known(value) where value <= CGFloat.ulpOfOne:
                break
            default:
                scrollToItem = ListViewScrollToItem(index: 0, position: .top(0.0), animated: true, curve: .Spring(duration: duration), directionHint: .Up)
            }
        }
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: scrollToItem, updateSizeAndInsets: ListViewUpdateSizeAndInsets(size: size, insets: UIEdgeInsets(top: topInset, left: sideInset, bottom: bottomInset, right: sideInset), duration: duration, curve: curve), stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
        
        self.listNode.scrollEnabled = !isScrollingLockedAtTop
        
        if isFirstLayout, let enclosingPeer = self.enclosingPeer, let state = self.currentState {
            self.updateState(enclosingPeer: enclosingPeer, state: state, presentationData: presentationData)
        }
    }
    
    private func updateState(enclosingPeer: Peer, state: PeerInfoMembersState, presentationData: PresentationData) {
        var entries: [PeerMembersListEntry] = []
        if state.canAddMembers {
            entries.append(.addMember(presentationData.theme, presentationData.strings.GroupInfo_AddParticipant))
        }
        for member in state.members {
            entries.append(.member(theme: presentationData.theme, index: entries.count, member: member))
        }
        
        let transaction = preparedTransition(from: self.currentEntries, to: entries, context: self.context, presentationData: presentationData, enclosingPeer: enclosingPeer, addMemberAction: { [weak self] in
            self?.addMemberAction()
        }, action: { [weak self] member, action in
            guard let self else {
                return
            }
            
            if case .open = action {
                self.listNode.clearHighlightAnimated(true)
            }
            
            self.action(member, action)
        }, contextAction: { [weak self] member, sourceNode, gesture in
            guard let self else {
                return
            }
            var node: ContextExtractedContentContainingNode?
            if let sourceNode = sourceNode as? ContextExtractedContentContainingNode {
                node = sourceNode
            } else {
                for subnode in sourceNode.subnodes ?? [] {
                    if let subnode = subnode as? ContextExtractedContentContainingNode {
                        node = subnode
                        break
                    }
                }
            }
            guard let node else {
                gesture?.cancel()
                return
            }
            
            let actions = availableActionsForMemberOfPeer(accountPeerId: self.context.account.peerId, peer: enclosingPeer, member: member)
            
            let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
            var items: [ContextMenuItem] = []
            let action = self.action
            
            if actions.contains(.promote) && enclosingPeer is TelegramChannel {
                items.append(.action(ContextMenuActionItem(text: presentationData.strings.GroupInfo_ActionPromote, icon: { _ in
                    return nil
                }, action: { c, _ in
                    c?.dismiss(completion: {
                        action(member, .promote)
                    })
                })))
            }
            if actions.contains(.restrict) {
                if enclosingPeer is TelegramChannel {
                    items.append(.action(ContextMenuActionItem(text: presentationData.strings.GroupInfo_ActionRestrict, icon: { _ in
                        return nil
                    }, action: { c, _ in
                        c?.dismiss(completion: {
                            action(member, .restrict)
                        })
                    })))
                }
                items.append(.action(ContextMenuActionItem(text: presentationData.strings.Common_Delete, textColor: .destructive, icon: { _ in
                    return nil
                }, action: { c, _ in
                    c?.dismiss(completion: {
                        action(member, .remove)
                    })
                })))
            }
            
            if items.isEmpty {
                gesture?.cancel()
                return
            }
            
            let dismissPromise = ValuePromise<Bool>(false)
            let source = PeerInfoMemberExtractedContentSource(sourceNode: node, keepInPlace: false, blurBackground: true, centerVertically: false, shouldBeDismissed: dismissPromise.get())
            
            let contextController = ContextController(presentationData: presentationData, source: .extracted(source), items: .single(ContextController.Items(content: .list(items))), gesture: gesture)
            self.parentController?.presentInGlobalOverlay(contextController)
        })
        self.enclosingPeer = enclosingPeer
        self.currentEntries = entries
        self.enqueuedTransactions.append(transaction)
        self.dequeueTransaction()
    }
    
    private func dequeueTransaction() {
        guard let _ = self.currentParams, let transaction = self.enqueuedTransactions.first else {
            return
        }
        
        self.enqueuedTransactions.remove(at: 0)
        
        var options = ListViewDeleteAndInsertOptions()
        if transaction.animated {
            options.insert(.AnimateInsertion)
        } else {
            options.insert(.Synchronous)
        }
        
        self.listNode.transaction(deleteIndices: transaction.deletions, insertIndicesAndItems: transaction.insertions, updateIndicesAndItems: transaction.updates, options: options, updateSizeAndInsets: nil, updateOpaqueState: nil, completion: { [weak self] _ in
            guard let strongSelf = self else {
                return
            }
            if !strongSelf.didSetReady {
                strongSelf.didSetReady = true
                strongSelf.ready.set(.single(true))
            }
        })
    }
    
    func findLoadedMessage(id: MessageId) -> Message? {
        return nil
    }
    
    func updateHiddenMedia() {
    }
    
    func transferVelocity(_ velocity: CGFloat) {
        if velocity > 0.0 {
            self.listNode.transferVelocity(velocity)
        }
    }
    
    func cancelPreviewGestures() {
    }
    
    func transitionNodeForGallery(messageId: MessageId, media: Media) -> (ASDisplayNode, CGRect, () -> (UIView?, UIView?))? {
        return nil
    }
    
    func addToTransitionSurface(view: UIView) {
    }
    
    func updateSelectedMessages(animated: Bool) {
    }
}

final class PeerInfoMemberExtractedContentSource: ContextExtractedContentSource {
    var keepInPlace: Bool
    let ignoreContentTouches: Bool = false
    let blurBackground: Bool

    private let sourceNode: ContextExtractedContentContainingNode
    
    var centerVertically: Bool
    var shouldBeDismissed: Signal<Bool, NoError>
    
    init(sourceNode: ContextExtractedContentContainingNode, keepInPlace: Bool, blurBackground: Bool, centerVertically: Bool, shouldBeDismissed: Signal<Bool, NoError>) {
        self.sourceNode = sourceNode
        self.keepInPlace = keepInPlace
        self.blurBackground = blurBackground
        self.centerVertically = centerVertically
        self.shouldBeDismissed = shouldBeDismissed
    }
    
    func takeView() -> ContextControllerTakeViewInfo? {
        return ContextControllerTakeViewInfo(containingItem: .node(self.sourceNode), contentAreaInScreenSpace: UIScreen.main.bounds)
    }
    
    func putBack() -> ContextControllerPutBackViewInfo? {
        return ContextControllerPutBackViewInfo(contentAreaInScreenSpace: UIScreen.main.bounds)
    }
}
