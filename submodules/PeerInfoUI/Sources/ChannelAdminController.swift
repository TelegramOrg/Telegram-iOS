import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import AlertUI
import PresentationDataUtils
import ItemListAvatarAndNameInfoItem
import Emoji
import LocalizedPeerData
import Markdown
import SendInviteLinkScreen
import OwnershipTransferController
import OldChannelsController

private let rankMaxLength: Int32 = 16

private final class ChannelAdminControllerArguments {
    let context: AccountContext
    let updateAdminRights: (Bool) -> Void
    let toggleRight: (RightsItem, TelegramChatAdminRightsFlags, Bool) -> Void
    let toggleRightWhileDisabled: (TelegramChatAdminRightsFlags, TelegramChatAdminRightsFlags) -> Void
    let transferOwnership: () -> Void
    let updateRank: (String, String) -> Void
    let updateFocusedOnRank: (Bool) -> Void
    let dismissAdmin: () -> Void
    let dismissInput: () -> Void
    let animateError: () -> Void
    let toggleIsOptionExpanded: (RightsItem.Sub) -> Void
    
    init(context: AccountContext, updateAdminRights: @escaping (Bool) -> Void, toggleRight: @escaping (RightsItem, TelegramChatAdminRightsFlags, Bool) -> Void, toggleRightWhileDisabled: @escaping (TelegramChatAdminRightsFlags, TelegramChatAdminRightsFlags) -> Void, transferOwnership: @escaping () -> Void, updateRank: @escaping (String, String) -> Void, updateFocusedOnRank: @escaping (Bool) -> Void, dismissAdmin: @escaping () -> Void, dismissInput: @escaping () -> Void, animateError: @escaping () -> Void, toggleIsOptionExpanded: @escaping (RightsItem.Sub) -> Void) {
        self.context = context
        self.updateAdminRights = updateAdminRights
        self.toggleRight = toggleRight
        self.toggleRightWhileDisabled = toggleRightWhileDisabled
        self.transferOwnership = transferOwnership
        self.updateRank = updateRank
        self.updateFocusedOnRank = updateFocusedOnRank
        self.dismissAdmin = dismissAdmin
        self.dismissInput = dismissInput
        self.animateError = animateError
        self.toggleIsOptionExpanded = toggleIsOptionExpanded
    }
}

private enum ChannelAdminSection: Int32 {
    case info
    case rank
    case adminRights
    case rights
    case transfer
    case dismiss
}

private enum ChannelAdminEntryTag: ItemListItemTag {
    case rank

    func isEqual(to other: ItemListItemTag) -> Bool {
        if let other = other as? ChannelAdminEntryTag, self == other {
            return true
        } else {
            return false
        }
    }
}

private enum ChannelAdminEntryStableId: Hashable {
    case info
    case rankTitle
    case rank
    case rankInfo
    case adminRights
    case rightsTitle
    case right(RightsItem)
    case addAdminsInfo
    case transfer
    case dismiss
}

private struct AdminSubPermission: Equatable {
    var title: String
    var flags: TelegramChatAdminRightsFlags
    var isSelected: Bool
    var isEnabled: Bool
}

enum RightsItem: Equatable, Hashable {
    enum Sub {
        case messages
        case stories
    }
    
    case direct(TelegramChatAdminRightsFlags)
    case sub(Sub, [TelegramChatAdminRightsFlags])
}

private let messageRelatedFlags: [TelegramChatAdminRightsFlags] = [
    .canPostMessages,
    .canEditMessages,
    .canDeleteMessages
]

private let storiesRelatedFlags: [TelegramChatAdminRightsFlags] = [
    .canPostStories,
    .canEditStories,
    .canDeleteStories
]

private enum ChannelAdminEntry: ItemListNodeEntry {
    case info(PresentationTheme, PresentationStrings, PresentationDateTimeFormat, EnginePeer, EnginePeer.Presence?)
    case rankTitle(PresentationTheme, String, Int32?, Int32)
    case rank(PresentationTheme, PresentationStrings, String, String, Bool)
    case rankInfo(PresentationTheme, String, Bool)
    case adminRights(PresentationTheme, String, Bool)
    case rightsTitle(PresentationTheme, String)
    case rightItem(PresentationTheme, Int, String, RightsItem, TelegramChatAdminRightsFlags, Bool, Bool, [AdminSubPermission], Bool)
    case addAdminsInfo(PresentationTheme, String)
    case transfer(PresentationTheme, String)
    case dismiss(PresentationTheme, String)
    
    var section: ItemListSectionId {
        switch self {
            case .info:
                return ChannelAdminSection.info.rawValue
            case .rankTitle, .rank, .rankInfo:
                return ChannelAdminSection.rank.rawValue
            case .adminRights:
                return ChannelAdminSection.adminRights.rawValue
            case .rightsTitle, .rightItem, .addAdminsInfo:
                return ChannelAdminSection.rights.rawValue
            case .transfer:
                return ChannelAdminSection.transfer.rawValue
            case .dismiss:
                return ChannelAdminSection.dismiss.rawValue
        }
    }
    
    var stableId: ChannelAdminEntryStableId {
        switch self {
            case .info:
                return .info
            case .rankTitle:
                return .rankTitle
            case .rank:
                return .rank
            case .rankInfo:
                return .rankInfo
            case .adminRights:
                return .adminRights
            case .rightsTitle:
                return .rightsTitle
            case let .rightItem(_, _, _, right, _, _, _, _, _):
                return .right(right)
            case .addAdminsInfo:
                return .addAdminsInfo
            case .transfer:
                return .transfer
            case .dismiss:
                return .dismiss
        }
    }
    
    static func ==(lhs: ChannelAdminEntry, rhs: ChannelAdminEntry) -> Bool {
        switch lhs {
            case let .info(lhsTheme, lhsStrings, lhsDateTimeFormat, lhsPeer, lhsPresence):
                if case let .info(rhsTheme, rhsStrings, rhsDateTimeFormat, rhsPeer, rhsPresence) = rhs {
                    if lhsTheme !== rhsTheme {
                        return false
                    }
                    if lhsStrings !== rhsStrings {
                        return false
                    }
                    if lhsDateTimeFormat != rhsDateTimeFormat {
                        return false
                    }
                    if lhsPeer != rhsPeer {
                        return false
                    }
                    if lhsPresence != rhsPresence {
                        return false
                    }
                    
                    return true
                } else {
                    return false
                }
            case let .rankTitle(lhsTheme, lhsText, lhsCount, lhsLimit):
                if case let .rankTitle(rhsTheme, rhsText, rhsCount, rhsLimit) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsCount == rhsCount, lhsLimit == rhsLimit {
                    return true
                } else {
                    return false
                }
            case let .rank(lhsTheme, lhsStrings, lhsPlaceholder, lhsValue, lhsEnabled):
                if case let .rank(rhsTheme, rhsStrings, rhsPlaceholder, rhsValue, rhsEnabled) = rhs, lhsTheme === rhsTheme, lhsStrings === rhsStrings, lhsPlaceholder == rhsPlaceholder, lhsValue == rhsValue, lhsEnabled == rhsEnabled {
                    return true
                } else {
                    return false
                }
            case let .rankInfo(lhsTheme, lhsText, lhsTrimBottomInset):
                if case let .rankInfo(rhsTheme, rhsText, rhsTrimBottomInset) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsTrimBottomInset == rhsTrimBottomInset {
                    return true
                } else {
                    return false
                }
            case let .adminRights(lhsTheme, lhsText, lhsValue):
                if case let .adminRights(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .rightsTitle(lhsTheme, lhsText):
                if case let .rightsTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .rightItem(lhsTheme, lhsIndex, lhsText, lhsRight, lhsFlags, lhsValue, lhsEnabled, lhsSubItems, lhsIsExpanded):
                if case let .rightItem(rhsTheme, rhsIndex, rhsText, rhsRight, rhsFlags, rhsValue, rhsEnabled, rhsSubItems, rhsIsExpanded) = rhs {
                    if lhsTheme !== rhsTheme {
                        return false
                    }
                    if lhsIndex != rhsIndex {
                        return false
                    }
                    if lhsText != rhsText {
                        return false
                    }
                    if lhsRight != rhsRight {
                        return false
                    }
                    if lhsFlags != rhsFlags {
                        return false
                    }
                    if lhsValue != rhsValue {
                        return false
                    }
                    if lhsEnabled != rhsEnabled {
                        return false
                    }
                    if lhsSubItems != rhsSubItems {
                        return false
                    }
                    if lhsIsExpanded != rhsIsExpanded {
                        return false
                    }
                    return true
                } else {
                    return false
                }
            case let .addAdminsInfo(lhsTheme, lhsText):
                if case let .addAdminsInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .transfer(lhsTheme, lhsText):
                if case let .transfer(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .dismiss(lhsTheme, lhsText):
                if case let .dismiss(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
        }
    }
    
    static func <(lhs: ChannelAdminEntry, rhs: ChannelAdminEntry) -> Bool {
        switch lhs {
            case .info:
                switch rhs {
                    case .info:
                        return false
                    default:
                        return true
                }
            case .adminRights:
                switch rhs {
                case .info, .adminRights:
                        return false
                    default:
                        return true
                }
            case .rightsTitle:
                switch rhs {
                    case .info, .adminRights, .rightsTitle:
                        return false
                    default:
                        return true
                }
            case let .rightItem(_, lhsIndex, _, _, _, _, _, _, _):
                switch rhs {
                    case .info, .adminRights, .rightsTitle:
                        return false
                    case let .rightItem(_, rhsIndex, _, _, _, _, _, _, _):
                        return lhsIndex < rhsIndex
                    default:
                        return true
                }
            case .addAdminsInfo:
                switch rhs {
                    case .info, .adminRights, .rightsTitle, .rightItem, .addAdminsInfo:
                        return false
                    default:
                        return true
                }
            case .transfer:
                switch rhs {
                    case .info, .adminRights, .rightsTitle, .rightItem, .addAdminsInfo, .transfer:
                        return false
                    default:
                        return true
                }
            case .rankTitle:
                switch rhs {
                    case .info, .adminRights, .rightsTitle, .rightItem, .addAdminsInfo, .transfer, .rankTitle:
                        return false
                    default:
                        return true
                }
            case .rank:
                switch rhs {
                    case .info, .adminRights, .rightsTitle, .rightItem, .addAdminsInfo, .transfer, .rankTitle, .rank:
                        return false
                    default:
                        return true
                }
            case .rankInfo:
                switch rhs {
                    case .info, .adminRights, .rightsTitle, .rightItem, .addAdminsInfo, .transfer, .rankTitle, .rank, .rankInfo:
                        return false
                    default:
                        return true
                }
            case .dismiss:
                return false
        }
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ChannelAdminControllerArguments
        switch self {
            case let .info(_, _, dateTimeFormat, peer, presence):
                return ItemListAvatarAndNameInfoItem(itemContext: .accountContext(arguments.context), presentationData: presentationData, dateTimeFormat: dateTimeFormat, mode: .generic, peer: peer, presence: presence, memberCount: nil, state: ItemListAvatarAndNameInfoItemState(), sectionId: self.section, style: .blocks(withTopInset: true, withExtendedBottomInset: false), editingNameUpdated: { _ in
                }, avatarTapped: {
                })
            case let .rankTitle(_, text, count, limit):
                var accessoryText: ItemListSectionHeaderAccessoryText?
                if let count = count {
                    accessoryText = ItemListSectionHeaderAccessoryText(value: "\(limit - count)", color: count > limit ? .destructive : .generic)
                }
                return ItemListSectionHeaderItem(presentationData: presentationData, text: text, accessoryText: accessoryText, sectionId: self.section)
            case let .rank(_, _, placeholder, text, enabled):
                return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "", textColor: .black), text: text, placeholder: placeholder, type: .regular(capitalization: false, autocorrection: true), spacing: 0.0, clearType: enabled ? .always : .none, enabled: enabled, tag: ChannelAdminEntryTag.rank, sectionId: self.section, textUpdated: { updatedText in
                    arguments.updateRank(text, updatedText)
                }, shouldUpdateText: { text in
                    if text.containsEmoji {
                        arguments.animateError()
                        return false
                    }
                    return true
                }, updatedFocus: { focus in
                    arguments.updateFocusedOnRank(focus)
                }, action: {
                    arguments.dismissInput()
                })
            case let .rankInfo(_, text, trimBottomInset):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section, additionalOuterInsets: UIEdgeInsets(top: 0.0, left: 0.0, bottom: trimBottomInset ? -44.0 : 0.0, right: 0.0))
            case let .adminRights(_, text, value):
                return ItemListSwitchItem(presentationData: presentationData, title: text, value: value, type: .regular, enabled: true, sectionId: self.section, style: .blocks, updated: { value in
                    arguments.updateAdminRights(value)
                }, activatedWhileDisabled: {
                })
            case let .rightsTitle(_, text):
                return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
            case let .rightItem(_, _, text, right, flags, value, enabled, subPermissions, isExpanded):
                if !subPermissions.isEmpty {
                    return ItemListExpandableSwitchItem(presentationData: presentationData, title: text, value: value, isExpanded: isExpanded, subItems: subPermissions.map { item in
                        return ItemListExpandableSwitchItem.SubItem(
                            id: AnyHashable(item.flags.rawValue),
                            title: item.title,
                            isSelected: item.isSelected,
                            isEnabled: item.isEnabled
                        )
                    }, type: .icon, enableInteractiveChanges: enabled, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                        if enabled {
                            arguments.toggleRight(right, flags, value)
                        } else {
                            //arguments.toggleRightWhileDisabled(right, flags)
                        }
                    }, activatedWhileDisabled: {
                        //arguments.toggleRightWhileDisabled(right, flags)
                    }, selectAction: {
                        if case let .sub(type, _) = right {
                            arguments.toggleIsOptionExpanded(type)
                        }
                    }, subAction: { item in
                        guard let value = item.id.base as? Int32 else {
                            return
                        }
                        let subRights = TelegramChatAdminRightsFlags(rawValue: value)
                        
                        if enabled {
                            arguments.toggleRight(.direct(subRights), flags, !item.isSelected)
                        } else {
                            arguments.toggleRightWhileDisabled(subRights, flags)
                        }
                    })
                } else {
                    return ItemListSwitchItem(presentationData: presentationData, title: text, value: value, type: .icon, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                        arguments.toggleRight(right, flags, value)
                    }, activatedWhileDisabled: {
                        if case let .direct(right) = right {
                            arguments.toggleRightWhileDisabled(right, flags)
                        }
                    })
                }
            case let .addAdminsInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
            case let .transfer(_, text):
                return ItemListActionItem(presentationData: presentationData, title: text, kind: .generic, alignment: .center, sectionId: self.section, style: .blocks, action: {
                    arguments.transferOwnership()
                }, tag: nil)
            case let .dismiss(_, text):
                return ItemListActionItem(presentationData: presentationData, title: text, kind: .destructive, alignment: .center, sectionId: self.section, style: .blocks, action: {
                    arguments.dismissAdmin()
                }, tag: nil)
        }
    }
}

private struct ChannelAdminControllerState: Equatable {
    var adminRights: Bool
    var updatedFlags: TelegramChatAdminRightsFlags?
    var updatedRank: String?
    var updating: Bool
    var focusedOnRank: Bool
    var expandedPermissions: Set<RightsItem.Sub> = Set()
    
    init(adminRights: Bool = true, updatedFlags: TelegramChatAdminRightsFlags? = nil, updatedRank: String? = nil, updating: Bool = false, focusedOnRank: Bool = false, expandedPermissions: Set<RightsItem.Sub> = Set()) {
        self.adminRights = adminRights
        self.updatedFlags = updatedFlags
        self.updatedRank = updatedRank
        self.updating = updating
        self.focusedOnRank = focusedOnRank
        self.expandedPermissions = expandedPermissions
    }
    
    static func ==(lhs: ChannelAdminControllerState, rhs: ChannelAdminControllerState) -> Bool {
        if lhs.adminRights != rhs.adminRights {
            return false
        }
        if lhs.updatedFlags != rhs.updatedFlags {
            return false
        }
        if lhs.updatedRank != rhs.updatedRank {
            return false
        }
        if lhs.updating != rhs.updating {
            return false
        }
        if lhs.focusedOnRank != rhs.focusedOnRank {
            return false
        }
        if lhs.expandedPermissions != rhs.expandedPermissions {
            return false
        }
        return true
    }
    
    func withUpdatedAdminRights(_ adminRights: Bool) -> ChannelAdminControllerState {
        return ChannelAdminControllerState(adminRights: adminRights, updatedFlags: self.updatedFlags, updatedRank: self.updatedRank, updating: self.updating, focusedOnRank: self.focusedOnRank, expandedPermissions: self.expandedPermissions)
    }
    
    func withUpdatedUpdatedFlags(_ updatedFlags: TelegramChatAdminRightsFlags?) -> ChannelAdminControllerState {
        return ChannelAdminControllerState(adminRights: self.adminRights, updatedFlags: updatedFlags, updatedRank: self.updatedRank, updating: self.updating, focusedOnRank: self.focusedOnRank, expandedPermissions: self.expandedPermissions)
    }
    
    func withUpdatedUpdatedRank(_ updatedRank: String?) -> ChannelAdminControllerState {
        return ChannelAdminControllerState(adminRights: self.adminRights, updatedFlags: self.updatedFlags, updatedRank: updatedRank, updating: self.updating, focusedOnRank: self.focusedOnRank, expandedPermissions: self.expandedPermissions)
    }
    
    func withUpdatedUpdating(_ updating: Bool) -> ChannelAdminControllerState {
        return ChannelAdminControllerState(adminRights: self.adminRights, updatedFlags: self.updatedFlags, updatedRank: self.updatedRank, updating: updating, focusedOnRank: self.focusedOnRank, expandedPermissions: self.expandedPermissions)
    }
    
    func withUpdatedFocusedOnRank(_ focusedOnRank: Bool) -> ChannelAdminControllerState {
        return ChannelAdminControllerState(adminRights: self.adminRights, updatedFlags: self.updatedFlags, updatedRank: self.updatedRank, updating: self.updating, focusedOnRank: focusedOnRank, expandedPermissions: self.expandedPermissions)
    }
}

private func stringForRight(strings: PresentationStrings, right: TelegramChatAdminRightsFlags, isGroup: Bool, isChannel: Bool, isForum: Bool, defaultBannedRights: TelegramChatBannedRights?) -> String {
    if right.contains(.canChangeInfo) {
        return isGroup ? strings.Group_EditAdmin_PermissionChangeInfo : strings.Channel_EditAdmin_PermissionChangeInfo
    } else if right.contains(.canPostMessages) {
        return strings.Channel_EditAdmin_PermissionPostMessages
    } else if right.contains(.canEditMessages) {
        if isChannel {
            return strings.Channel_EditAdmin_PermissionEditMessagesOfOthers
        } else {
            return strings.Channel_EditAdmin_PermissionEditMessages
        }
    } else if right.contains(.canDeleteMessages) {
        return isGroup ? strings.Channel_EditAdmin_PermissionDeleteMessages : strings.Channel_EditAdmin_PermissionDeleteMessagesOfOthers
    } else if right.contains(.canBanUsers) {
        return strings.Channel_EditAdmin_PermissionBanUsers
    } else if right.contains(.canInviteUsers) {
        if isGroup {
            if let defaultBannedRights = defaultBannedRights, defaultBannedRights.flags.contains(.banAddMembers) {
                return strings.Channel_EditAdmin_PermissionInviteMembers
            } else {
                return strings.Channel_EditAdmin_PermissionInviteViaLink
            }
        } else {
            return strings.Channel_EditAdmin_PermissionInviteSubscribers
        }
    } else if right.contains(.canPinMessages) {
        return strings.Channel_EditAdmin_PermissionPinMessages
    } else if right.contains(.canManageTopics) {
        return strings.Channel_EditAdmin_PermissionManageTopics
    } else if right.contains(.canAddAdmins) {
        return strings.Channel_EditAdmin_PermissionAddAdmins
    } else if right.contains(.canBeAnonymous) {
        return strings.Channel_AdminLog_CanBeAnonymous
    } else if right.contains(.canManageCalls) {
        if isChannel {
            return strings.Channel_AdminLog_CanManageLiveStreams
        } else {
            return strings.Channel_AdminLog_CanManageCalls
        }
    } else if right.contains(.canManageDirect) {
        return strings.Channel_AdminLog_CanManageDirect
    } else if right.contains(.canPostStories) {
        return strings.Channel_EditAdmin_PermissionPostStories
    } else if right.contains(.canEditStories) {
        return strings.Channel_EditAdmin_PermissionEditStoriesOfOthers
    } else if right.contains(.canDeleteStories) {
        return strings.Channel_EditAdmin_PermissionDeleteStoriesOfOthers
    } else {
        return ""
    }
}

private func rightDependencies(_ right: TelegramChatAdminRightsFlags) -> [TelegramChatAdminRightsFlags] {
    if right.contains(.canChangeInfo) {
        return []
    } else if right.contains(.canPostMessages) {
        return []
    } else if right.contains(.canEditMessages) {
        return []
    } else if right.contains(.canDeleteMessages) {
        return []
    } else if right.contains(.canBanUsers) {
        return []
    } else if right.contains(.canInviteUsers) {
        return []
    } else if right.contains(.canPinMessages) {
        return []
    } else if right.contains(.canAddAdmins) {
        return []
    } else if right.contains(.canManageDirect) {
        return []
    } else if right.contains(.canManageCalls) {
        return []
    } else if right.contains(.canBeAnonymous) {
        return []
    } else {
        return []
    }
}

private func canEditAdminRights(accountPeerId: EnginePeer.Id, channelPeer: EnginePeer, initialParticipant: ChannelParticipant?) -> Bool {
    if case let .channel(channel) = channelPeer {
        if channel.flags.contains(.isCreator) {
            return true
        } else if let initialParticipant = initialParticipant {
            switch initialParticipant {
                case .creator:
                    return false
                case let .member(_, _, adminInfo, _, _, _):
                    if let adminInfo = adminInfo {
                        return adminInfo.canBeEditedByAccountPeer || adminInfo.promotedBy == accountPeerId
                    } else {
                        return channel.hasPermission(.addAdmins)
                    }
            }
        } else {
            return channel.hasPermission(.addAdmins)
        }
    } else if case let .legacyGroup(group) = channelPeer {
        if case .creator = group.role {
            return true
        } else {
            return false
        }
    } else {
        return false
    }
}

private func rightEnabledByDefault(channelPeer: EnginePeer, right: TelegramChatAdminRightsFlags) -> Bool {
    if case let .channel(channel) = channelPeer {
        guard let defaultBannedRights = channel.defaultBannedRights else {
            return false
        }
        switch right {
        case .canPinMessages:
            return !defaultBannedRights.flags.contains(.banPinMessages)
        case .canChangeInfo:
            return !defaultBannedRights.flags.contains(.banChangeInfo)
        default:
            break
        }
    }
    return false
}

private func areAllAdminRightsEnabled(_ flags: TelegramChatAdminRightsFlags, peer: EnginePeer, except: TelegramChatAdminRightsFlags) -> Bool {
    return TelegramChatAdminRightsFlags.peerSpecific(peer: peer).subtracting(except).intersection(flags) == TelegramChatAdminRightsFlags.peerSpecific(peer: peer).subtracting(except)
}

private func channelAdminControllerEntries(presentationData: PresentationData, state: ChannelAdminControllerState, accountPeerId: EnginePeer.Id, channelPeer: EnginePeer?, adminPeer: EnginePeer?, adminPresence: EnginePeer.Presence?, initialParticipant: ChannelParticipant?, invite: Bool, canEdit: Bool) -> [ChannelAdminEntry] {
    var entries: [ChannelAdminEntry] = []
    
    if case let .channel(channel) = channelPeer, let admin = adminPeer {
        entries.append(.info(presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, admin, adminPresence))

        var isChannel = false
        if case .broadcast = channel.info {
            isChannel = true
        }
        
        var isCreator = false
        if let initialParticipant = initialParticipant, case .creator = initialParticipant {
            isCreator = true
        }
        
        var canTransfer = false
        var canDismiss = false
        
        let isGroup: Bool
        var maskRightsFlags: TelegramChatAdminRightsFlags
        
        let rightsOrder: [RightsItem]
        
        maskRightsFlags = TelegramChatAdminRightsFlags.peerSpecific(peer: .channel(channel))
        switch channel.info {
            case .broadcast:
                isGroup = false
                rightsOrder = [
                    .direct(.canChangeInfo),
                    .sub(.messages, messageRelatedFlags),
                    .sub(.stories, storiesRelatedFlags),
                    .direct(.canInviteUsers),
                    .direct(.canManageDirect),
                    .direct(.canManageCalls),
                    .direct(.canAddAdmins)
                ]
            case .group:
                isGroup = true
                if channel.flags.contains(.isForum) {
                    rightsOrder = [
                        .direct(.canChangeInfo),
                        .direct(.canDeleteMessages),
                        .direct(.canBanUsers),
                        .direct(.canInviteUsers),
                        .direct(.canPinMessages),
                        .direct(.canManageTopics),
                        .direct(.canManageCalls),
                        .direct(.canBeAnonymous),
                        .direct(.canAddAdmins)
                    ]
                } else {
                    rightsOrder = [
                        .direct(.canChangeInfo),
                        .direct(.canDeleteMessages),
                        .direct(.canBanUsers),
                        .direct(.canInviteUsers),
                        .direct(.canPinMessages),
                        .sub(.stories, storiesRelatedFlags),
                        .direct(.canManageCalls),
                        .direct(.canBeAnonymous),
                        .direct(.canAddAdmins)
                    ]
                }
        }
        
        if isCreator {
            if isGroup {
                entries.append(.rightsTitle(presentationData.theme, presentationData.strings.Channel_EditAdmin_PermissionsHeader))
                
                let accountUserRightsFlags: TelegramChatAdminRightsFlags
                if channel.flags.contains(.isCreator) {
                    accountUserRightsFlags = maskRightsFlags
                } else if let adminRights = channel.adminRights {
                    accountUserRightsFlags = maskRightsFlags.intersection(adminRights.rights)
                } else {
                    accountUserRightsFlags = []
                }
                
                let currentRightsFlags: TelegramChatAdminRightsFlags
                if let updatedFlags = state.updatedFlags {
                    currentRightsFlags = updatedFlags
                } else if let initialParticipant = initialParticipant, case let .member(_, _, maybeAdminRights, _, _, _) = initialParticipant, let adminRights = maybeAdminRights {
                    currentRightsFlags = adminRights.rights.rights
                } else if let initialParticipant = initialParticipant, case let .creator(_, maybeAdminRights, _) = initialParticipant, let adminRights = maybeAdminRights {
                    currentRightsFlags = adminRights.rights.rights
                } else {
                    currentRightsFlags = accountUserRightsFlags.subtracting(.canAddAdmins).subtracting(.canBeAnonymous)
                }
                
                var index = 0
                rightsLoop: for right in rightsOrder {
                    let enabled: Bool
                    let isSelected: Bool
                    let itemTitle: String
                    var subItems: [AdminSubPermission] = []
                    var isExpanded = false
                    
                    switch right {
                    case let .direct(right):
                        if !accountUserRightsFlags.contains(right) {
                            continue rightsLoop
                        }
                        
                        enabled = right == .canBeAnonymous
                        
                        itemTitle = stringForRight(strings: presentationData.strings, right: right, isGroup: isGroup, isChannel: isChannel, isForum: channel.flags.contains(.isForum), defaultBannedRights: channel.defaultBannedRights)
                        isSelected = currentRightsFlags.contains(right)
                    case let .sub(type, subRights):
                        let filteredSubRights = subRights.filter({ accountUserRightsFlags.contains($0) })
                        if filteredSubRights.isEmpty {
                            continue rightsLoop
                        }
                        
                        enabled = true
                        
                        switch type {
                        case .messages:
                            itemTitle = presentationData.strings.Channel_EditAdmin_SectionMessages
                        case .stories:
                            itemTitle = presentationData.strings.Channel_EditAdmin_SectionStories
                        }
                        
                        isSelected = subRights.allSatisfy({ currentRightsFlags.contains($0) })
                        
                        isExpanded = state.expandedPermissions.contains(type)
                        
                        for subRight in filteredSubRights {
                            let subRightEnabled = true
                            
                            subItems.append(AdminSubPermission(title: stringForRight(strings: presentationData.strings, right: subRight, isGroup: isGroup, isChannel: isChannel, isForum: channel.flags.contains(.isForum), defaultBannedRights: channel.defaultBannedRights), flags: subRight, isSelected: currentRightsFlags.contains(subRight), isEnabled: enabled && subRightEnabled))
                        }
                    }
                    
                    entries.append(.rightItem(presentationData.theme, index, itemTitle, right, currentRightsFlags, isSelected, enabled, subItems, isExpanded))
                    index += 1
                }
            }
        } else {
            if case let .user(adminPeer) = adminPeer, adminPeer.botInfo != nil, case .group = channel.info, invite, let channelPeer = channelPeer, canEditAdminRights(accountPeerId: accountPeerId, channelPeer: channelPeer, initialParticipant: initialParticipant) {
                if let initialParticipant = initialParticipant, case let .member(_, _, adminInfo, _, _, _) = initialParticipant, adminInfo != nil {
                    
                } else {
                    entries.append(.adminRights(presentationData.theme, presentationData.strings.Bot_AddToChat_Add_AdminRights, state.adminRights))
                }
            }
            
            if !invite || state.adminRights {
                entries.append(.rightsTitle(presentationData.theme, presentationData.strings.Channel_EditAdmin_PermissionsHeader))
            
                if let channelPeer = channelPeer, canEditAdminRights(accountPeerId: accountPeerId, channelPeer: channelPeer, initialParticipant: initialParticipant) {
                    let accountUserRightsFlags: TelegramChatAdminRightsFlags
                    if channel.flags.contains(.isCreator) {
                        accountUserRightsFlags = maskRightsFlags
                    } else if let adminRights = channel.adminRights {
                        accountUserRightsFlags = maskRightsFlags.intersection(adminRights.rights)
                    } else {
                        accountUserRightsFlags = []
                    }
                    
                    let currentRightsFlags: TelegramChatAdminRightsFlags
                    if let updatedFlags = state.updatedFlags {
                        currentRightsFlags = updatedFlags
                    } else if let initialParticipant = initialParticipant, case let .member(_, _, maybeAdminRights, _, _, _) = initialParticipant, let adminRights = maybeAdminRights {
                        currentRightsFlags = adminRights.rights.rights
                    } else {
                        currentRightsFlags = accountUserRightsFlags.subtracting(.canAddAdmins).subtracting(.canBeAnonymous)
                    }
                    
                    var index = 0
                    rightsLoop: for right in rightsOrder {
                        let enabled: Bool
                        let isSelected: Bool
                        let itemTitle: String
                        var subItems: [AdminSubPermission] = []
                        var isExpanded = false
                        
                        switch right {
                        case let .direct(right):
                            if !accountUserRightsFlags.contains(right) {
                                continue rightsLoop
                            }
                            
                            enabled = !state.updating && admin.id != accountPeerId && !rightEnabledByDefault(channelPeer: .channel(channel), right: right)
                            
                            itemTitle = stringForRight(strings: presentationData.strings, right: right, isGroup: isGroup, isChannel: isChannel, isForum: channel.flags.contains(.isForum), defaultBannedRights: channel.defaultBannedRights)
                            isSelected = currentRightsFlags.contains(right)
                        case let .sub(type, subRights):
                            let filteredSubRights = subRights.filter({ accountUserRightsFlags.contains($0) })
                            if filteredSubRights.isEmpty {
                                continue rightsLoop
                            }
                            
                            enabled = !state.updating
                            
                            switch type {
                            case .messages:
                                itemTitle = presentationData.strings.Channel_EditAdmin_SectionMessages
                            case .stories:
                                itemTitle = presentationData.strings.Channel_EditAdmin_SectionStories
                            }
                            
                            isSelected = subRights.allSatisfy({ currentRightsFlags.contains($0) })
                            
                            isExpanded = state.expandedPermissions.contains(type)
                            
                            for subRight in filteredSubRights {
                                let subRightEnabled = !state.updating && admin.id != accountPeerId && !rightEnabledByDefault(channelPeer: .channel(channel), right: subRight)
                                
                                subItems.append(AdminSubPermission(title: stringForRight(strings: presentationData.strings, right: subRight, isGroup: isGroup, isChannel: isChannel, isForum: channel.flags.contains(.isForum), defaultBannedRights: channel.defaultBannedRights), flags: subRight, isSelected: currentRightsFlags.contains(subRight), isEnabled: enabled && subRightEnabled))
                            }
                        }
                            
                        entries.append(.rightItem(presentationData.theme, index, itemTitle, right, currentRightsFlags, isSelected, enabled, subItems, isExpanded))
                        index += 1
                    }
                    
                    if accountUserRightsFlags.contains(.canAddAdmins) {
                        entries.append(.addAdminsInfo(presentationData.theme, currentRightsFlags.contains(.canAddAdmins) ? presentationData.strings.Channel_EditAdmin_PermissinAddAdminOn : presentationData.strings.Channel_EditAdmin_PermissinAddAdminOff))
                    }
                    
                    if case let .user(admin) = admin, admin.botInfo == nil && !admin.isDeleted && channel.flags.contains(.isCreator) && areAllAdminRightsEnabled(currentRightsFlags, peer: .channel(channel), except: .canBeAnonymous) {
                        canTransfer = true
                    }
                
                    if let initialParticipant = initialParticipant, case let .member(_, _, adminInfo, _, _, _) = initialParticipant, admin.id != accountPeerId, adminInfo != nil {
                        if channel.flags.contains(.isCreator) {
                            canDismiss = true
                        } else {
                            switch initialParticipant {
                                case .creator:
                                    break
                                case let .member(_, _, adminInfo, _, _, _):
                                    if let adminInfo = adminInfo {
                                        if adminInfo.promotedBy == accountPeerId || adminInfo.canBeEditedByAccountPeer {
                                            canDismiss = true
                                        }
                                    }
                            }
                        }
                    }
                } else if let initialParticipant = initialParticipant, case let .member(_, _, maybeAdminInfo, _, _, _) = initialParticipant, let adminInfo = maybeAdminInfo {
                    var index = 0
                    rightsLoop: for right in rightsOrder {
                        let enabled: Bool = false
                        let isSelected: Bool
                        let itemTitle: String
                        var subItems: [AdminSubPermission] = []
                        var isExpanded = false
                        
                        switch right {
                        case let .direct(right):
                            itemTitle = stringForRight(strings: presentationData.strings, right: right, isGroup: isGroup, isChannel: isChannel, isForum: channel.flags.contains(.isForum), defaultBannedRights: channel.defaultBannedRights)
                            isSelected = adminInfo.rights.rights.contains(right)
                        case let .sub(type, subRights):
                            let filteredSubRights = subRights
                            if filteredSubRights.isEmpty {
                                continue rightsLoop
                            }
                            
                            switch type {
                            case .messages:
                                itemTitle = presentationData.strings.Channel_EditAdmin_SectionMessages
                            case .stories:
                                itemTitle = presentationData.strings.Channel_EditAdmin_SectionStories
                            }
                            
                            isSelected = subRights.allSatisfy({ adminInfo.rights.rights.contains($0) })
                            
                            isExpanded = state.expandedPermissions.contains(type)
                            
                            for subRight in filteredSubRights {
                                let subRightEnabled = false
                                
                                subItems.append(AdminSubPermission(title: stringForRight(strings: presentationData.strings, right: subRight, isGroup: isGroup, isChannel: isChannel, isForum: channel.flags.contains(.isForum), defaultBannedRights: channel.defaultBannedRights), flags: subRight, isSelected: adminInfo.rights.rights.contains(subRight), isEnabled: enabled && subRightEnabled))
                            }
                        }
                        
                        entries.append(.rightItem(presentationData.theme, index, itemTitle, right, adminInfo.rights.rights, isSelected, enabled, subItems, isExpanded))
                        index += 1
                    }
                }
            }
        }
        
        if !invite || state.adminRights {
            if canTransfer {
                entries.append(.transfer(presentationData.theme, isGroup ? presentationData.strings.Group_EditAdmin_TransferOwnership : presentationData.strings.Channel_EditAdmin_TransferOwnership))
            }
            
            if case .group = channel.info {
                let placeholder = isCreator ? presentationData.strings.Group_EditAdmin_RankOwnerPlaceholder : presentationData.strings.Group_EditAdmin_RankAdminPlaceholder
                
                let currentRank: String?
                if let updatedRank = state.updatedRank {
                    currentRank = updatedRank
                } else if let initialParticipant = initialParticipant {
                    currentRank = initialParticipant.rank
                } else {
                    currentRank = nil
                }
                
                let rankEnabled = !state.updating && canEdit
                entries.append(.rankTitle(presentationData.theme, presentationData.strings.Group_EditAdmin_RankTitle.uppercased(), rankEnabled && state.focusedOnRank ? Int32(currentRank?.count ?? 0) : nil, rankMaxLength))
                entries.append(.rank(presentationData.theme, presentationData.strings, isCreator ? presentationData.strings.Group_EditAdmin_RankOwnerPlaceholder : presentationData.strings.Group_EditAdmin_RankAdminPlaceholder, currentRank ?? "", rankEnabled))
                entries.append(.rankInfo(presentationData.theme, presentationData.strings.Group_EditAdmin_RankInfo(placeholder).string, invite))
            }
        }
        
        if canDismiss {
            entries.append(.dismiss(presentationData.theme, presentationData.strings.Channel_Moderator_AccessLevelRevoke))
        }
    } else if case let .legacyGroup(group) = channelPeer, let admin = adminPeer {
        entries.append(.info(presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, admin, adminPresence))
        
        var isCreator = false
        if let initialParticipant = initialParticipant, case .creator = initialParticipant {
            isCreator = true
        }
        
        let currentRank: String?
        if let updatedRank = state.updatedRank {
            currentRank = updatedRank
        } else {
            currentRank = nil
        }
        
        let rankEnabled = !state.updating && canEdit
        
        if isCreator {
            entries.append(.rankTitle(presentationData.theme, presentationData.strings.Group_EditAdmin_RankTitle.uppercased(), rankEnabled && state.focusedOnRank ? Int32(currentRank?.count ?? 0) : nil, rankMaxLength))
            entries.append(.rank(presentationData.theme, presentationData.strings, isCreator ? presentationData.strings.Group_EditAdmin_RankOwnerPlaceholder : presentationData.strings.Group_EditAdmin_RankAdminPlaceholder, currentRank ?? "", rankEnabled))
        } else {
            if case let .user(adminPeer) = adminPeer, adminPeer.botInfo != nil, invite {
                if let initialParticipant = initialParticipant, case let .member(_, _, adminRights, _, _, _) = initialParticipant, adminRights != nil {
                } else {
                    entries.append(.adminRights(presentationData.theme, presentationData.strings.Bot_AddToChat_Add_AdminRights, state.adminRights))
                }
            }
            
            var accountIsCreator = false
            if case .creator = group.role {
                accountIsCreator = true
            }
            
            if !invite || state.adminRights {
                entries.append(.rightsTitle(presentationData.theme, presentationData.strings.Channel_EditAdmin_PermissionsHeader))
                
                let isGroup = true
                let isChannel = false
                let maskRightsFlags: TelegramChatAdminRightsFlags = TelegramChatAdminRightsFlags.peerSpecific(peer: .legacyGroup(group))
                let rightsOrder: [TelegramChatAdminRightsFlags] = [
                    .canChangeInfo,
                    .canDeleteMessages,
                    .canBanUsers,
                    .canInviteUsers,
                    .canPinMessages,
                    .canManageCalls,
                    .canBeAnonymous,
                    .canAddAdmins
                ]
                                
                let accountUserRightsFlags: TelegramChatAdminRightsFlags = maskRightsFlags
            
                let currentRightsFlags: TelegramChatAdminRightsFlags
                if let updatedFlags = state.updatedFlags {
                    currentRightsFlags = updatedFlags
                } else if let initialParticipant = initialParticipant, case let .member(_, _, maybeAdminRights, _, _, _) = initialParticipant, let adminRights = maybeAdminRights {
                    currentRightsFlags = adminRights.rights.rights.subtracting(.canAddAdmins).subtracting(.canBeAnonymous)
                } else {
                    currentRightsFlags = accountUserRightsFlags.subtracting(.canAddAdmins).subtracting(.canBeAnonymous)
                }
                            
                var index = 0
                for right in rightsOrder {
                    if accountUserRightsFlags.contains(right) {
                        entries.append(.rightItem(presentationData.theme, index, stringForRight(strings: presentationData.strings, right: right, isGroup: isGroup, isChannel: isChannel, isForum: false, defaultBannedRights: group.defaultBannedRights), .direct(right), currentRightsFlags, currentRightsFlags.contains(right), !state.updating && accountIsCreator, [], false))
                        index += 1
                    }
                }
            
                if accountUserRightsFlags.contains(.canAddAdmins) {
                    entries.append(.addAdminsInfo(presentationData.theme, currentRightsFlags.contains(.canAddAdmins) ? presentationData.strings.Channel_EditAdmin_PermissinAddAdminOn : presentationData.strings.Channel_EditAdmin_PermissinAddAdminOff))
                }
            
                if case let .user(admin) = admin, case .creator = group.role, admin.botInfo == nil && !admin.isDeleted && areAllAdminRightsEnabled(currentRightsFlags, peer: .legacyGroup(group), except: .canBeAnonymous) {
                    entries.append(.transfer(presentationData.theme, presentationData.strings.Group_EditAdmin_TransferOwnership))
                }
                
                let placeholder = isCreator ? presentationData.strings.Group_EditAdmin_RankOwnerPlaceholder : presentationData.strings.Group_EditAdmin_RankAdminPlaceholder
                entries.append(.rankTitle(presentationData.theme, presentationData.strings.Group_EditAdmin_RankTitle.uppercased(), rankEnabled && state.focusedOnRank ? Int32(currentRank?.count ?? 0) : nil, rankMaxLength))
                entries.append(.rank(presentationData.theme, presentationData.strings, placeholder, currentRank ?? "", rankEnabled))
                entries.append(.rankInfo(presentationData.theme, presentationData.strings.Group_EditAdmin_RankInfo(placeholder).string, invite))
            }
            
            if let initialParticipant = initialParticipant, case let .member(_, _, adminInfo, _, _, _) = initialParticipant, admin.id != accountPeerId, let adminInfo {
                var canDismiss = false
                if accountIsCreator {
                    canDismiss = true
                } else if adminInfo.promotedBy == accountPeerId || adminInfo.canBeEditedByAccountPeer {
                    canDismiss = true
                }
                if canDismiss {
                    entries.append(.dismiss(presentationData.theme, presentationData.strings.Channel_Moderator_AccessLevelRevoke))
                }
            }
        }
    }
    
    return entries
}

public func channelAdminController(context: AccountContext, updatedPresentationData: (initial: PresentationData, signal: Signal<PresentationData, NoError>)? = nil, peerId: EnginePeer.Id, adminId: EnginePeer.Id, initialParticipant: ChannelParticipant?, invite: Bool = false, initialAdminRights: TelegramChatAdminRightsFlags? = nil, updated: @escaping (TelegramChatAdminRights?) -> Void, upgradedToSupergroup: @escaping (EnginePeer.Id, @escaping () -> Void) -> Void, transferedOwnership: @escaping (EnginePeer.Id) -> Void) -> ViewController {
    let statePromise = ValuePromise(ChannelAdminControllerState(), ignoreRepeated: true)
    let stateValue = Atomic(value: ChannelAdminControllerState())
    let updateState: ((ChannelAdminControllerState) -> ChannelAdminControllerState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }
    
    if let initialAdminRights = initialAdminRights {
        updateState {
            return $0.withUpdatedUpdatedFlags(initialAdminRights)
        }
    }
    
    let actionsDisposable = DisposableSet()
    
    let updateRightsDisposable = MetaDisposable()
    actionsDisposable.add(updateRightsDisposable)
    
    let transferOwnershipDisposable = MetaDisposable()
    actionsDisposable.add(transferOwnershipDisposable)
    
    var dismissImpl: (() -> Void)?
    var dismissInputImpl: (() -> Void)?
    var presentControllerImpl: ((ViewController, Any?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    var errorImpl: (() -> Void)?
    var scrollToRankImpl: (() -> Void)?
    
    let actualPeerId = Atomic<EnginePeer.Id>(value: peerId)
    let upgradedToSupergroupImpl: (EnginePeer.Id, @escaping () -> Void) -> Void = { peerId, completion in
        let _ = actualPeerId.swap(peerId)
        upgradedToSupergroup(peerId, completion)
    }
    
    let arguments = ChannelAdminControllerArguments(context: context, updateAdminRights: { value in
        updateState { current in
            return current.withUpdatedAdminRights(value)
        }
    }, toggleRight: { right, flags, value in
        updateState { current in
            var updated = flags
            
            var combinedRight: TelegramChatAdminRightsFlags
            switch right {
            case let .direct(right):
                combinedRight = right
            case let .sub(_, right):
                combinedRight = []
                for flag in right {
                    combinedRight.insert(flag)
                }
            }
            
            if !value {
                updated.remove(combinedRight)
            } else {
                updated.insert(combinedRight)
            }
            return current.withUpdatedUpdatedFlags(updated)
        }
    }, toggleRightWhileDisabled: { right, _ in
        let _ = (context.engine.data.get(
            TelegramEngine.EngineData.Item.Peer.Peer(id: peerId),
            TelegramEngine.EngineData.Item.Peer.Peer(id: adminId)
        )
        |> deliverOnMainQueue).start(next: { peer, member in
            guard let peer = peer, case .user = member else {
                return
            }
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            
            let text: String
            if !canEditAdminRights(accountPeerId: context.account.peerId, channelPeer: peer, initialParticipant: initialParticipant) {
                text = presentationData.strings.Channel_EditAdmin_CannotEdit
            } else if rightEnabledByDefault(channelPeer: peer, right: right) {
                text = presentationData.strings.Channel_EditAdmin_PermissionEnabledByDefault
            } else {
                text = presentationData.strings.Channel_EditAdmin_CannotEdit
            }
            
            presentControllerImpl?(standardTextAlertController(theme: AlertControllerTheme(presentationData: presentationData), title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
        })
    }, transferOwnership: {
        let _ = (context.engine.data.get(
            TelegramEngine.EngineData.Item.Peer.Peer(id: peerId),
            TelegramEngine.EngineData.Item.Peer.Peer(id: adminId)
        )
        |> deliverOnMainQueue).start(next: { peer, member in
            guard let peer = peer, case let .user(member) = member else {
                return
            }
            
            transferOwnershipDisposable.set((context.engine.peers.checkOwnershipTranfserAvailability(memberId: adminId) |> deliverOnMainQueue).start(error: { error in
                let controller = channelOwnershipTransferController(context: context, updatedPresentationData: updatedPresentationData, peer: peer, member: member, initialError: error, present: { c, a in
                    presentControllerImpl?(c, a)
                }, completion: { upgradedPeerId in
                    if let upgradedPeerId = upgradedPeerId {
                        upgradedToSupergroupImpl(upgradedPeerId, {
                            dismissImpl?()
                            transferedOwnership(member.id)
                        })
                    } else {
                        dismissImpl?()
                        transferedOwnership(member.id)
                    }
                })
                presentControllerImpl?(controller, nil)
            }))
        })
    }, updateRank: { previousRank, updatedRank in
        if updatedRank != previousRank {
            updateState { $0.withUpdatedUpdatedRank(updatedRank) }
        }
    }, updateFocusedOnRank: { focusedOnRank in
        updateState { $0.withUpdatedFocusedOnRank(focusedOnRank) }
        
        if focusedOnRank {
            scrollToRankImpl?()
        }
    }, dismissAdmin: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        items.append(ActionSheetButtonItem(title: presentationData.strings.Channel_Moderator_AccessLevelRevoke, color: .destructive, font: .default, enabled: true, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
            
            updateState { current in
                return current.withUpdatedUpdating(true)
            }
            if peerId.namespace == Namespaces.Peer.CloudGroup {
                updateRightsDisposable.set((context.engine.peers.removeGroupAdmin(peerId: peerId, adminId: adminId)
                |> deliverOnMainQueue).start(error: { _ in
                }, completed: {
                    updated(nil)
                    dismissImpl?()
                }))
            } else {
                updateRightsDisposable.set((context.peerChannelMemberCategoriesContextsManager.updateMemberAdminRights(engine: context.engine, peerId: peerId, memberId: adminId, adminRights: nil, rank: nil) |> deliverOnMainQueue).start(error: { _ in
                    
                }, completed: {
                    updated(nil)
                    dismissImpl?()
                }))
            }
        }))
        actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])])
        presentControllerImpl?(actionSheet, nil)
    }, dismissInput: {
        dismissInputImpl?()
    }, animateError: {
        errorImpl?()
    }, toggleIsOptionExpanded: { flag in
        updateState { state in
            var state = state
            
            if state.expandedPermissions.contains(flag) {
                state.expandedPermissions.remove(flag)
            } else {
                state.expandedPermissions.insert(flag)
            }
            
            return state
        }
    })
    
    let presentationData = updatedPresentationData?.signal ?? context.sharedContext.presentationData
    let signal = combineLatest(
        queue: .mainQueue(),
        presentationData,
        statePromise.get(),
        context.engine.data.subscribe(
            TelegramEngine.EngineData.Item.Peer.Peer(id: peerId),
            TelegramEngine.EngineData.Item.Peer.Peer(id: adminId),
            TelegramEngine.EngineData.Item.Peer.Presence(id: adminId)
        ),
        context.engine.data.subscribe(
            TelegramEngine.EngineData.Item.Peer.ExportedInvitation(id: peerId)
        )
    )
    |> deliverOnMainQueue
    |> map { presentationData, state, peerInfoData, exportedInvitation -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let channelPeer = peerInfoData.0.flatMap { $0 }
        let adminPeer = peerInfoData.1.flatMap { $0 }
        let adminPresence = peerInfoData.2
        let canEdit = canEditAdminRights(accountPeerId: context.account.peerId, channelPeer: channelPeer!, initialParticipant: initialParticipant)
        
        let leftNavigationButton: ItemListNavigationButton
        if canEdit {
            leftNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Cancel), style: .regular, enabled: true, action: {
                dismissImpl?()
            })
        } else {
            leftNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: true, action: {
                dismissImpl?()
            })
        }
                
        let rightButtonActionImpl = {
            if invite && !state.adminRights {
                updateState { current in
                    return current.withUpdatedUpdating(true)
                }
                if let channelPeer, case let .channel(channel) = channelPeer {
                    updateRightsDisposable.set((context.engine.peers.addChannelMember(peerId: peerId, memberId: adminId)
                    |> deliverOnMainQueue).start(error: { error in
                        updateState { current in
                            return current.withUpdatedUpdating(false)
                        }
                        
                        if let adminPeer, case let .restricted(forbiddenPeer) = error {
                            let inviteScreen = SendInviteLinkScreen(context: context, subject: .chat(peer: channelPeer, link: exportedInvitation?.link), peers: [forbiddenPeer ?? TelegramForbiddenInvitePeer(peer: adminPeer, canInviteWithPremium: false, premiumRequiredToContact: false)])
                            pushControllerImpl?(inviteScreen)
                            
                            dismissImpl?()
                            
                            return
                        }

                        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                        var text = presentationData.strings.Login_UnknownError
                        switch error {
                        case .tooMuchJoined:
                            text = presentationData.strings.Group_ErrorSupergroupConversionNotPossible
                        case .restricted:
                            if let admin = adminPeer {
                                switch channel.info {
                                    case .broadcast:
                                        text = presentationData.strings.Privacy_GroupsAndChannels_InviteToChannelError(admin.compactDisplayTitle, admin.compactDisplayTitle).string
                                    case .group:
                                        text = presentationData.strings.Privacy_GroupsAndChannels_InviteToGroupError(admin.compactDisplayTitle, admin.compactDisplayTitle).string
                                }
                            }
                        case .notMutualContact:
                            if case .broadcast = channel.info {
                                text = presentationData.strings.Channel_AddUserLeftError
                            } else {
                                text = presentationData.strings.GroupInfo_AddUserLeftError
                            }
                        default:
                            break
                        }
                        presentControllerImpl?(textAlertController(context: context, updatedPresentationData: updatedPresentationData, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
                    }, completed: {
                        updated(nil)
                        dismissImpl?()
                    }))
                } else if case .legacyGroup = channelPeer {
                    updateRightsDisposable.set((context.engine.peers.addGroupMember(peerId: peerId, memberId: adminId) |> deliverOnMainQueue).start(error: { error in
                        updateState { current in
                            return current.withUpdatedUpdating(false)
                        }
                        if case .privacy = error, let admin = adminPeer {
                            presentControllerImpl?(textAlertController(context: context, updatedPresentationData: updatedPresentationData, title: nil, text: presentationData.strings.Privacy_GroupsAndChannels_InviteToGroupError(admin.compactDisplayTitle, admin.compactDisplayTitle).string, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
                        }
                    }, completed: {
                        updated(nil)
                        dismissImpl?()
                    }))
                }
            } else if case let .channel(channel) = channelPeer {
                if let initialParticipant = initialParticipant {
                    var updateFlags: TelegramChatAdminRightsFlags?
                    var updateRank: String?
                    updateState { current in
                        updateFlags = current.updatedFlags
                        updateRank = current.updatedRank?.trimmingCharacters(in: .whitespacesAndNewlines)
                        return current
                    }
                    
                    if let updateRank = updateRank, updateRank.count > rankMaxLength || updateRank.containsEmoji {
                        errorImpl?()
                        return
                    }
                    
                    let maskRightsFlags: TelegramChatAdminRightsFlags = TelegramChatAdminRightsFlags.peerSpecific(peer: .channel(channel))
                    
                    var currentRank: String?
                    var currentFlags: TelegramChatAdminRightsFlags?
                    switch initialParticipant {
                        case let .creator(_, adminInfo, rank):
                            currentRank = rank
                            currentFlags = adminInfo?.rights.rights ?? maskRightsFlags.subtracting(.canBeAnonymous)
                        case let .member(_, _, adminInfo, _, rank, _):
                            if updateFlags == nil {
                                if adminInfo?.rights == nil {
                                    if channel.flags.contains(.isCreator) {
                                        updateFlags = maskRightsFlags.subtracting([.canAddAdmins, .canBeAnonymous])
                                    } else if let adminRights = channel.adminRights {
                                        updateFlags = maskRightsFlags.intersection(adminRights.rights).subtracting([.canAddAdmins, .canBeAnonymous])
                                    } else {
                                        updateFlags = []
                                    }
                                } else {
                                    updateFlags = adminInfo?.rights.rights
                                }
                            }
                            currentRank = rank
                            currentFlags = adminInfo?.rights.rights
                    }
                    
                    let effectiveRank = updateRank ?? currentRank
                    if effectiveRank?.containsEmoji ?? false {
                        errorImpl?()
                        return
                    }
                    
                    if let updateFlags, updateFlags != currentFlags {
                        updateState { current in
                            return current.withUpdatedUpdating(true)
                        }
                        updateRightsDisposable.set((context.peerChannelMemberCategoriesContextsManager.updateMemberAdminRights(engine: context.engine, peerId: peerId, memberId: adminId, adminRights: TelegramChatAdminRights(rights: updateFlags), rank: effectiveRank) |> deliverOnMainQueue).start(error: { error in
                            updateState { current in
                                return current.withUpdatedUpdating(false)
                            }
                            
                            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                            var text = presentationData.strings.Login_UnknownError
                            switch error {
                            case .generic:
                                break
                            case let .addMemberError(addMemberError):
                                switch addMemberError {
                                case .tooMuchJoined:
                                    text = presentationData.strings.Group_ErrorSupergroupConversionNotPossible
                                case .restricted:
                                    if let admin = adminPeer {
                                        switch channel.info {
                                            case .broadcast:
                                                text = presentationData.strings.Privacy_GroupsAndChannels_InviteToChannelError(admin.compactDisplayTitle, admin.compactDisplayTitle).string
                                            case .group:
                                                text = presentationData.strings.Privacy_GroupsAndChannels_InviteToGroupError(admin.compactDisplayTitle, admin.compactDisplayTitle).string
                                        }
                                    }
                                case .notMutualContact:
                                    if case .broadcast = channel.info {
                                        text = presentationData.strings.Channel_AddUserLeftError
                                    } else {
                                        text = presentationData.strings.GroupInfo_AddUserLeftError
                                    }
                                default:
                                    break
                                }
                            case .adminsTooMuch:
                                if case .broadcast = channel.info {
                                    text = presentationData.strings.Channel_ErrorAdminsTooMuch
                                } else {
                                    text = presentationData.strings.Group_ErrorAdminsTooMuch
                                }
                            }
                            presentControllerImpl?(textAlertController(context: context, updatedPresentationData: updatedPresentationData, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
                        }, completed: {
                            updated(TelegramChatAdminRights(rights: updateFlags))
                            dismissImpl?()
                        }))
                    } else if let updateRank = updateRank, let currentFlags = currentFlags {
                        updateState { current in
                            return current.withUpdatedUpdating(true)
                        }
                        updateRightsDisposable.set((context.peerChannelMemberCategoriesContextsManager.updateMemberAdminRights(engine: context.engine, peerId: peerId, memberId: adminId, adminRights: TelegramChatAdminRights(rights: currentFlags), rank: updateRank) |> deliverOnMainQueue).start(error: { _ in
                            
                        }, completed: {
                            updated(TelegramChatAdminRights(rights: currentFlags))
                            dismissImpl?()
                        }))
                    } else {
                        dismissImpl?()
                    }
                } else if canEdit {
                    var updateFlags: TelegramChatAdminRightsFlags?
                    var updateRank: String?
                    updateState { current in
                        updateFlags = current.updatedFlags
                        updateRank = current.updatedRank?.trimmingCharacters(in: .whitespacesAndNewlines)
                        return current
                    }
                    
                    if let updateRank = updateRank, updateRank.count > rankMaxLength || updateRank.containsEmoji {
                        errorImpl?()
                        return
                    }
                    
                    if updateFlags == nil {
                        let maskRightsFlags: TelegramChatAdminRightsFlags = TelegramChatAdminRightsFlags.peerSpecific(peer: .channel(channel))
                        
                        if channel.flags.contains(.isCreator) {
                            updateFlags = maskRightsFlags.subtracting([.canAddAdmins, .canBeAnonymous])
                        } else if let adminRights = channel.adminRights {
                            updateFlags = maskRightsFlags.intersection(adminRights.rights).subtracting([.canAddAdmins, .canBeAnonymous])
                        } else {
                            updateFlags = []
                        }
                    }
                    
                    if let updateFlags = updateFlags {
                        updateState { current in
                            return current.withUpdatedUpdating(true)
                        }
                        updateRightsDisposable.set((context.peerChannelMemberCategoriesContextsManager.updateMemberAdminRights(engine: context.engine, peerId: peerId, memberId: adminId, adminRights: TelegramChatAdminRights(rights: updateFlags), rank: updateRank) |> deliverOnMainQueue).start(error: { error in
                            if case let .addMemberError(addMemberError) = error, case let .restricted(forbiddenPeer) = addMemberError, let admin = adminPeer {
                                if let channelPeer {
                                    let inviteScreen = SendInviteLinkScreen(context: context, subject: .chat(peer: channelPeer, link: exportedInvitation?.link), peers: [forbiddenPeer ?? TelegramForbiddenInvitePeer(peer: admin, canInviteWithPremium: false, premiumRequiredToContact: false)])
                                    pushControllerImpl?(inviteScreen)
                                    
                                    dismissImpl?()
                                    
                                    return
                                }
                                
                                var text = presentationData.strings.Login_UnknownError
                                switch addMemberError {
                                    case .tooMuchJoined:
                                        text = presentationData.strings.Group_ErrorSupergroupConversionNotPossible
                                    case .restricted:
                                        switch channel.info {
                                            case .broadcast:
                                                text = presentationData.strings.Privacy_GroupsAndChannels_InviteToChannelError(admin.compactDisplayTitle, admin.compactDisplayTitle).string
                                            case .group:
                                                text = presentationData.strings.Privacy_GroupsAndChannels_InviteToGroupError(admin.compactDisplayTitle, admin.compactDisplayTitle).string
                                        }
                                    case .notMutualContact:
                                        if case .broadcast = channel.info {
                                            text = presentationData.strings.Channel_AddUserLeftError
                                        } else {
                                            text = presentationData.strings.GroupInfo_AddUserLeftError
                                        }
                                    default:
                                        break
                                }
                                presentControllerImpl?(textAlertController(context: context, updatedPresentationData: updatedPresentationData, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
                            } else if case .adminsTooMuch = error {
                                let text: String
                                if case .broadcast = channel.info {
                                    text = presentationData.strings.Channel_ErrorAdminsTooMuch
                                } else {
                                    text = presentationData.strings.Group_ErrorAdminsTooMuch
                                }
                                presentControllerImpl?(textAlertController(context: context, updatedPresentationData: updatedPresentationData, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
                            }
                            dismissImpl?()
                        }, completed: {
                            updated(TelegramChatAdminRights(rights: updateFlags))
                            dismissImpl?()
                        }))
                    }
                }
            } else if case let .legacyGroup(group) = channelPeer {
                var updateFlags: TelegramChatAdminRightsFlags?
                var updateRank: String?
                updateState { current in
                    updateFlags = current.updatedFlags
                    if let updatedRank = current.updatedRank, !updatedRank.isEmpty {
                        updateRank = updatedRank.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    return current
                }
                
                if let updateRank = updateRank, updateRank.count > rankMaxLength || updateRank.containsEmoji {
                    errorImpl?()
                    return
                }
                
                let maskRightsFlags: TelegramChatAdminRightsFlags = TelegramChatAdminRightsFlags.peerSpecific(peer: .legacyGroup(group))
                let defaultFlags = maskRightsFlags.subtracting([.canBeAnonymous, .canAddAdmins])
                
                if updateFlags == nil {
                    updateFlags = defaultFlags
                }
                
                if let updateFlags = updateFlags {
                    if initialParticipant?.adminInfo == nil && updateFlags == defaultFlags && updateRank == nil {
                        updateState { current in
                            return current.withUpdatedUpdating(true)
                        }
                        updateRightsDisposable.set((context.engine.peers.addGroupAdmin(peerId: peerId, adminId: adminId)
                        |> deliverOnMainQueue).start(error: { error in
                            if case let .addMemberError(error) = error, case let .privacy(privacy) = error, let admin = adminPeer {
                                if let failedPeer = privacy?.forbiddenPeers.first {
                                    let _ = (context.engine.data.get(
                                        TelegramEngine.EngineData.Item.Peer.ExportedInvitation(id: group.id)
                                    )
                                    |> deliverOnMainQueue).startStandalone(next: { exportedInvitation in
                                        let _ = exportedInvitation
                                        let inviteScreen = SendInviteLinkScreen(context: context, subject: .chat(peer: .legacyGroup(group), link: exportedInvitation?.link), peers: [failedPeer])
                                        pushControllerImpl?(inviteScreen)
                                    })
                                } else {
                                    presentControllerImpl?(textAlertController(context: context, updatedPresentationData: updatedPresentationData, title: nil, text: presentationData.strings.Privacy_GroupsAndChannels_InviteToGroupError(admin.compactDisplayTitle, admin.compactDisplayTitle).string, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
                                }
                            } else if case .adminsTooMuch = error {
                                presentControllerImpl?(textAlertController(context: context, updatedPresentationData: updatedPresentationData, title: nil, text: presentationData.strings.Group_ErrorAdminsTooMuch, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
                            }
                            
                            dismissImpl?()
                        }, completed: {
                            dismissImpl?()
                        }))
                    } else if updateFlags != defaultFlags || updateRank != nil {
                        enum WrappedUpdateChannelAdminRightsError {
                            case direct(UpdateChannelAdminRightsError)
                            case conversionTooManyChannels
                            case conversionFailed
                        }
                        
                        let signal = context.engine.peers.convertGroupToSupergroup(peerId: peerId)
                        |> map(Optional.init)
                        |> `catch` { error -> Signal<EnginePeer.Id?, WrappedUpdateChannelAdminRightsError> in
                            switch error {
                            case .tooManyChannels:
                                return .fail(.conversionTooManyChannels)
                            default:
                                return .fail(.conversionFailed)
                            }
                        }
                        |> mapToSignal { upgradedPeerId -> Signal<EnginePeer.Id?, WrappedUpdateChannelAdminRightsError> in
                            guard let upgradedPeerId = upgradedPeerId else {
                                return .fail(.conversionFailed)
                            }
                            return context.peerChannelMemberCategoriesContextsManager.updateMemberAdminRights(engine: context.engine, peerId: upgradedPeerId, memberId: adminId, adminRights: TelegramChatAdminRights(rights: updateFlags), rank: updateRank)
                            |> mapError { error -> WrappedUpdateChannelAdminRightsError in
                                return .direct(error)
                            }
                            |> mapToSignal { _ -> Signal<EnginePeer.Id?, WrappedUpdateChannelAdminRightsError> in
                                return .complete()
                            }
                            |> then(.single(upgradedPeerId))
                        }
                        |> deliverOnMainQueue
                        
                        updateState { current in
                            return current.withUpdatedUpdating(true)
                        }
                        updateRightsDisposable.set(signal.start(next: { upgradedPeerId in
                            if let upgradedPeerId = upgradedPeerId {
                                upgradedToSupergroup(upgradedPeerId, {
                                    dismissImpl?()
                                })
                            }
                        }, error: { error in
                            updateState { current in
                                return current.withUpdatedUpdating(false)
                            }
                            
                            switch error {
                            case let .direct(error):
                                if case let .addMemberError(error) = error {
                                    var text = presentationData.strings.Login_UnknownError
                                    if case .restricted = error, let admin = adminPeer {
                                        text = presentationData.strings.Privacy_GroupsAndChannels_InviteToGroupError(admin.compactDisplayTitle, admin.compactDisplayTitle).string
                                    } else if case .tooMuchJoined = error {
                                        text = presentationData.strings.Invite_ChannelsTooMuch
                                    } else if case .kicked = error {
                                        text = presentationData.strings.Channel_AddAdminKickedError
                                    }
                                    presentControllerImpl?(textAlertController(context: context, updatedPresentationData: updatedPresentationData, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
                                } else if case .adminsTooMuch = error {
                                    presentControllerImpl?(textAlertController(context: context, updatedPresentationData: updatedPresentationData, title: nil, text: presentationData.strings.Group_ErrorAdminsTooMuch, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
                                }
                            case .conversionFailed, .conversionTooManyChannels:
                                pushControllerImpl?(oldChannelsController(context: context, intent: .upgrade))
                            }
                            
                            dismissImpl?()
                        }))
                    } else {
                        dismissImpl?()
                    }
                } else {
                    dismissImpl?()
                }
            }
        }
        
        var rightNavigationButton: ItemListNavigationButton?
        if state.updating {
            rightNavigationButton = ItemListNavigationButton(content: .none, style: .activity, enabled: true, action: {})
        } else if canEdit {
            rightNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: true, action: {
                rightButtonActionImpl()
            })
        }
        
        var footerItem: ItemListControllerFooterItem?
        
        let title: String
        if initialParticipant?.adminInfo == nil {
            var isGroup: Bool = false
            var peerTitle: String = ""
            if case let .legacyGroup(peer) = channelPeer {
                isGroup = true
                peerTitle = peer.title
            } else if case let .channel(peer) = channelPeer {
                if case .group = peer.info {
                    isGroup = true
                }
                peerTitle = peer.title
            }
                
            if case let .user(admin) = adminPeer, admin.botInfo != nil && invite {
                title = presentationData.strings.Bot_AddToChat_Add_Title
                rightNavigationButton = nil
                footerItem = ChannelAdminAddBotFooterItem(theme: presentationData.theme, title: state.adminRights ? presentationData.strings.Bot_AddToChat_Add_AddAsAdmin : presentationData.strings.Bot_AddToChat_Add_AddAsMember, action: {
                    if state.adminRights {
                        let theme = AlertControllerTheme(presentationData: presentationData)
                        let attributedTitle = NSAttributedString(string: presentationData.strings.Bot_AddToChat_Add_AdminAlertTitle, font: Font.semibold(presentationData.listsFontSize.baseDisplaySize), textColor: theme.primaryColor, paragraphAlignment: .center)
                      
                        let text = isGroup ? presentationData.strings.Bot_AddToChat_Add_AdminAlertTextGroup(peerTitle).string : presentationData.strings.Bot_AddToChat_Add_AdminAlertTextChannel(peerTitle).string
                        
                        let body = MarkdownAttributeSet(font: Font.regular(presentationData.listsFontSize.baseDisplaySize * 13.0 / 17.0), textColor: theme.primaryColor)
                        let bold = MarkdownAttributeSet(font: Font.semibold(presentationData.listsFontSize.baseDisplaySize * 13.0 / 17.0), textColor: theme.primaryColor)
                        let attributedText = parseMarkdownIntoAttributedString(text, attributes: MarkdownAttributes(body: body, bold: bold, link: body, linkAttribute: { _ in return nil }), textAlignment: .center)
                                               
                        let controller = richTextAlertController(context: context, title: attributedTitle, text: attributedText, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Bot_AddToChat_Add_AdminAlertAdd, action: {
                            rightButtonActionImpl()
                        }), TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {
                        })], actionLayout: .vertical)
                        presentControllerImpl?(controller, nil)
                    } else {
                        rightButtonActionImpl()
                    }
                })
            } else {
                title = presentationData.strings.Channel_Management_AddModerator
            }
        } else {
            title = presentationData.strings.Channel_Moderator_Title
        }
        
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: leftNavigationButton, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: channelAdminControllerEntries(presentationData: presentationData, state: state, accountPeerId: context.account.peerId, channelPeer: channelPeer, adminPeer: adminPeer, adminPresence: adminPresence, initialParticipant: initialParticipant, invite: invite, canEdit: canEdit), style: .blocks, focusItemTag: nil, ensureVisibleItemTag: nil, emptyStateItem: nil, footerItem: footerItem, animateChanges: true)
        
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        actionsDisposable.dispose()
    }
    
    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .modal
    controller.experimentalSnapScrollToItem = true
    dismissImpl = { [weak controller] in
        controller?.view.endEditing(true)
        controller?.dismiss()
    }
    dismissInputImpl = { [weak controller] in
        controller?.view.endEditing(true)
    }
    presentControllerImpl = { [weak controller] value, presentationArguments in
        controller?.present(value, in: .window(.root), with: presentationArguments)
    }
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    
    let hapticFeedback = HapticFeedback()
    errorImpl = { [weak controller] in
        hapticFeedback.error()
        controller?.forEachItemNode { itemNode in
            if let itemNode = itemNode as? ItemListSingleLineInputItemNode {
                itemNode.animateError()
            }
        }
    }
    scrollToRankImpl = { [weak controller] in
        controller?.afterLayout({
            guard let controller = controller else {
                return
            }
            
            var resultItemNode: ListViewItemNode?
            let _ = controller.frameForItemNode({ itemNode in
                if let itemNode = itemNode as? ItemListSingleLineInputItemNode {
                    if let tag = itemNode.tag as? ChannelAdminEntryTag, tag == .rank {
                        resultItemNode = itemNode
                        return true
                    }
                }
                return false
            })
            if let resultItemNode = resultItemNode {
                Queue.mainQueue().after(0.1) {
                    controller.ensureItemNodeVisible(resultItemNode, atTop: true)
                }
            }
        })
    }
    
    return controller
}
