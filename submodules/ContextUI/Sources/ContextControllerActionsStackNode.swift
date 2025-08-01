import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import TextSelectionNode
import TelegramCore
import SwiftSignalKit
import AccountContext
import ReactionSelectionNode
import Markdown
import EntityKeyboard
import AnimationCache
import MultiAnimationRenderer
import AnimationUI
import ComponentFlow
import LottieComponent
import TextNodeWithEntities

public protocol ContextControllerActionsStackItemNode: ASDisplayNode {
    var wantsFullWidth: Bool { get }
    
    func update(
        presentationData: PresentationData,
        constrainedSize: CGSize,
        standardMinWidth: CGFloat,
        standardMaxWidth: CGFloat,
        additionalBottomInset: CGFloat,
        transition: ContainedViewLayoutTransition
    ) -> (size: CGSize, apparentHeight: CGFloat)
    
    func highlightGestureMoved(location: CGPoint)
    func highlightGestureFinished(performAction: Bool)
    
    func decreaseHighlightedIndex()
    func increaseHighlightedIndex()
}

public struct ContextControllerReactionItems {
    public var context: AccountContext
    public var reactionItems: [ReactionContextItem]
    public var selectedReactionItems: Set<MessageReaction.Reaction>
    public var reactionsTitle: String?
    public var reactionsLocked: Bool
    public var animationCache: AnimationCache
    public var alwaysAllowPremiumReactions: Bool
    public var allPresetReactionsAreAvailable: Bool
    public var getEmojiContent: ((AnimationCache, MultiAnimationRenderer) -> Signal<EmojiPagerContentComponent, NoError>)?
    
    public init(context: AccountContext, reactionItems: [ReactionContextItem], selectedReactionItems: Set<MessageReaction.Reaction>, reactionsTitle: String?, reactionsLocked: Bool, animationCache: AnimationCache, alwaysAllowPremiumReactions: Bool, allPresetReactionsAreAvailable: Bool, getEmojiContent: ((AnimationCache, MultiAnimationRenderer) -> Signal<EmojiPagerContentComponent, NoError>)?) {
        self.context = context
        self.reactionItems = reactionItems
        self.selectedReactionItems = selectedReactionItems
        self.reactionsTitle = reactionsTitle
        self.reactionsLocked = reactionsLocked
        self.animationCache = animationCache
        self.alwaysAllowPremiumReactions = alwaysAllowPremiumReactions
        self.allPresetReactionsAreAvailable = allPresetReactionsAreAvailable
        self.getEmojiContent = getEmojiContent
    }
}

public final class ContextControllerPreviewReaction {
    public let context: AccountContext
    public let file: TelegramMediaFile
    
    public init(context: AccountContext, file: TelegramMediaFile) {
        self.context = context
        self.file = file
    }
}

public protocol ContextControllerActionsStackItem: AnyObject {
    func node(
        context: AccountContext?,
        getController: @escaping () -> ContextControllerProtocol?,
        requestDismiss: @escaping (ContextMenuActionResult) -> Void,
        requestUpdate: @escaping (ContainedViewLayoutTransition) -> Void,
        requestUpdateApparentHeight: @escaping (ContainedViewLayoutTransition) -> Void
    ) -> ContextControllerActionsStackItemNode
    
    var id: AnyHashable? { get }
    var tip: ContextController.Tip? { get }
    var tipSignal: Signal<ContextController.Tip?, NoError>? { get }
    var reactionItems: ContextControllerReactionItems? { get }
    var previewReaction: ContextControllerPreviewReaction? { get }
    var dismissed: (() -> Void)? { get }
}

public protocol ContextControllerActionsListItemNode: ASDisplayNode {
    func update(presentationData: PresentationData, constrainedSize: CGSize) -> (minSize: CGSize, apply: (_ size: CGSize, _ transition: ContainedViewLayoutTransition) -> Void)
    
    func canBeHighlighted() -> Bool
    func updateIsHighlighted(isHighlighted: Bool)
    func performAction()
}

public final class ContextControllerActionsListActionItemNode: HighlightTrackingButtonNode, ContextControllerActionsListItemNode {
    private let context: AccountContext?
    private let getController: () -> ContextControllerProtocol?
    private let requestDismiss: (ContextMenuActionResult) -> Void
    private let requestUpdateAction: (AnyHashable, ContextMenuActionItem) -> Void
    private var item: ContextMenuActionItem
    
    private let highlightBackgroundNode: ASDisplayNode
    private let titleLabelNode: ImmediateTextNodeWithEntities
    private let subtitleNode: ImmediateTextNode
    private let iconNode: ASImageNode
    private let additionalIconNode: ASImageNode
    private var badgeIconNode: ASImageNode?
    private var animationNode: AnimationNode?
    
    private var currentAnimatedIconContent: ContextMenuActionItem.IconAnimation?
    private var animatedIcon: ComponentView<Empty>?
    
    private var currentBadge: (badge: ContextMenuActionBadge, image: UIImage)?
    
    private var iconDisposable: Disposable?
    
    public init(
        context: AccountContext?,
        getController: @escaping () -> ContextControllerProtocol?,
        requestDismiss: @escaping (ContextMenuActionResult) -> Void,
        requestUpdateAction: @escaping (AnyHashable, ContextMenuActionItem) -> Void,
        item: ContextMenuActionItem
    ) {
        self.context = context
        self.getController = getController
        self.requestDismiss = requestDismiss
        self.requestUpdateAction = requestUpdateAction
        self.item = item
        
        self.highlightBackgroundNode = ASDisplayNode()
        self.highlightBackgroundNode.isAccessibilityElement = false
        self.highlightBackgroundNode.isUserInteractionEnabled = false
        self.highlightBackgroundNode.alpha = 0.0
        
        self.titleLabelNode = ImmediateTextNodeWithEntities()
        self.titleLabelNode.isAccessibilityElement = false
        self.titleLabelNode.displaysAsynchronously = false
        
        self.subtitleNode = ImmediateTextNode()
        self.subtitleNode.isAccessibilityElement = false
        self.subtitleNode.displaysAsynchronously = false
        self.subtitleNode.isUserInteractionEnabled = false
        
        self.iconNode = ASImageNode()
        self.iconNode.isAccessibilityElement = false
        self.iconNode.isUserInteractionEnabled = false
        
        self.additionalIconNode = ASImageNode()
        self.additionalIconNode.isAccessibilityElement = false
        self.additionalIconNode.isUserInteractionEnabled = false
                
        super.init()
        
        self.isAccessibilityElement = true
        self.accessibilityLabel = item.text
        self.accessibilityTraits = [.button]
        
        self.addSubnode(self.highlightBackgroundNode)
        self.addSubnode(self.titleLabelNode)
        self.addSubnode(self.subtitleNode)
        self.addSubnode(self.iconNode)
        self.addSubnode(self.additionalIconNode)
        
        self.isEnabled = self.canBeHighlighted()
        
        self.highligthedChanged = { [weak self] highlighted in
            guard let strongSelf = self else {
                return
            }
            if highlighted {
                strongSelf.highlightBackgroundNode.alpha = 1.0
                strongSelf.startTimer()
            } else {
                strongSelf.highlightBackgroundNode.alpha = 0.0
                strongSelf.invalidateTimer()
            }
        }
        
        self.addTarget(self, action: #selector(self.pressed), forControlEvents: .touchUpInside)
    }
    
    deinit {
        self.iconDisposable?.dispose()
    }
        
    private var timer: SwiftSignalKit.Timer?
    private func startTimer() {
        self.invalidateTimer()
        
        self.timer = SwiftSignalKit.Timer(timeout: 1.0, repeat: false, completion: { [weak self] in
            guard let self else {
                return
            }
            self.invalidateTimer()
            self.longPressed()
        }, queue: Queue.mainQueue())
        self.timer?.start()
    }
    
    private func invalidateTimer() {
        self.timer?.invalidate()
        self.timer = nil
    }
    
    public override func didLoad() {
        super.didLoad()
        
        self.view.isExclusiveTouch = true
    }
    
    @objc private func pressed() {
        self.invalidateTimer()
        
        self.item.action?(ContextMenuActionItem.Action(
            controller: self.getController(),
            dismissWithResult: { [weak self] result in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.requestDismiss(result)
            },
            updateAction: { [weak self] id, updatedAction in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.requestUpdateAction(id, updatedAction)
            }
        ))
    }
    
    private func longPressed() {
        self.touchesCancelled(nil, with: nil)
        
        self.item.longPressAction?(ContextMenuActionItem.Action(
            controller: self.getController(),
            dismissWithResult: { [weak self] result in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.requestDismiss(result)
            },
            updateAction: { [weak self] id, updatedAction in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.requestUpdateAction(id, updatedAction)
            }
        ))
    }
    
    public func canBeHighlighted() -> Bool {
        return self.item.action != nil
    }
    
    public func updateIsHighlighted(isHighlighted: Bool) {
        self.highlightBackgroundNode.alpha = isHighlighted ? 1.0 : 0.0
    }
    
    public func performAction() {
        self.pressed()
    }
    
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if self.titleLabelNode.tapAttributeAction != nil {
            if let result = self.titleLabelNode.hitTest(self.view.convert(point, to: self.titleLabelNode.view), with: event) {
                return result
            }
        }
        
        return super.hitTest(point, with: event)
    }
    
    public func setItem(item: ContextMenuActionItem) {
        self.item = item
        self.accessibilityLabel = item.text
    }
    
    public func update(presentationData: PresentationData, constrainedSize: CGSize) -> (minSize: CGSize, apply: (_ size: CGSize, _ transition: ContainedViewLayoutTransition) -> Void) {
        let sideInset: CGFloat = 16.0
        let verticalInset: CGFloat = 11.0
        let titleSubtitleSpacing: CGFloat = 1.0
        let iconSideInset: CGFloat = 12.0
        let standardIconWidth: CGFloat = 32.0
        let iconSpacing: CGFloat = 8.0
        
        self.highlightBackgroundNode.backgroundColor = presentationData.theme.contextMenu.itemHighlightedBackgroundColor
                
        var forcedHeight: CGFloat?
        var titleVerticalOffset: CGFloat?
        let titleFont: UIFont
        let titleBoldFont: UIFont
        switch self.item.textFont {
        case let .custom(font, height, verticalOffset):
            titleFont = font
            titleBoldFont = font
            forcedHeight = height
            titleVerticalOffset = verticalOffset
        case .small:
            let smallTextFont = Font.regular(floor(presentationData.listsFontSize.baseDisplaySize * 14.0 / 17.0))
            titleFont = smallTextFont
            titleBoldFont = Font.semibold(floor(presentationData.listsFontSize.baseDisplaySize * 14.0 / 17.0))
        case .regular:
            titleFont = Font.regular(presentationData.listsFontSize.baseDisplaySize)
            titleBoldFont = Font.semibold(presentationData.listsFontSize.baseDisplaySize)
        }
        
        let subtitleFont = Font.regular(presentationData.listsFontSize.baseDisplaySize * 14.0 / 17.0)
        let subtitleColor = presentationData.theme.contextMenu.secondaryColor
        
        if let context = self.context {
            self.titleLabelNode.arguments = TextNodeWithEntities.Arguments(
                context: context,
                cache: context.animationCache,
                renderer: context.animationRenderer,
                placeholderColor: presentationData.theme.contextMenu.primaryColor.withMultipliedAlpha(0.1),
                attemptSynchronous: true
            )
        }
        self.titleLabelNode.visibility = self.item.enableEntityAnimations
        
        var subtitle: NSAttributedString?
        switch self.item.textLayout {
        case .singleLine:
            self.titleLabelNode.maximumNumberOfLines = 1
        case .twoLinesMax:
            self.titleLabelNode.maximumNumberOfLines = 2
        case let .secondLineWithValue(subtitleValue):
            self.titleLabelNode.maximumNumberOfLines = 1
            subtitle = NSAttributedString(
                string: subtitleValue,
                font: subtitleFont,
                textColor: subtitleColor
            )
        case let .secondLineWithAttributedValue(subtitleValue):
            self.titleLabelNode.maximumNumberOfLines = 1
            let mutableString = subtitleValue.mutableCopy() as! NSMutableAttributedString
            mutableString.addAttribute(.foregroundColor, value: subtitleColor, range: NSRange(location: 0, length: mutableString.length))
            mutableString.addAttribute(.font, value: subtitleFont, range: NSRange(location: 0, length: mutableString.length))
            subtitle = mutableString
        case .multiline:
            self.titleLabelNode.maximumNumberOfLines = 0
            self.titleLabelNode.lineSpacing = 0.1
        }
        
        let titleColor: UIColor
        switch self.item.textColor {
        case .primary:
            titleColor = presentationData.theme.contextMenu.primaryColor
        case .destructive:
            titleColor = presentationData.theme.contextMenu.destructiveColor
        case .disabled:
            titleColor = presentationData.theme.contextMenu.primaryColor.withMultipliedAlpha(0.4)
        }
        
        if self.item.parseMarkdown || !self.item.entities.isEmpty {
            let attributedText: NSAttributedString
            if !self.item.entities.isEmpty {
                let inputStateText = ChatTextInputStateText(text: self.item.text, attributes: self.item.entities.compactMap { entity -> ChatTextInputStateTextAttribute? in
                    if case let .CustomEmoji(_, fileId) = entity.type {
                        return ChatTextInputStateTextAttribute(type: .customEmoji(stickerPack: nil, fileId: fileId, enableAnimation: true), range: entity.range)
                    } else if case .Bold = entity.type {
                        return ChatTextInputStateTextAttribute(type: .bold, range: entity.range)
                    } else if case .Italic = entity.type {
                        return ChatTextInputStateTextAttribute(type: .italic, range: entity.range)
                    }
                    return nil
                })
                let result = NSMutableAttributedString(attributedString: inputStateText.attributedText(files: self.item.entityFiles))
                result.addAttributes([
                    .font: titleFont,
                    .foregroundColor: titleColor
                ], range: NSRange(location: 0, length: result.length))
                for attribute in inputStateText.attributes {
                    if case .bold = attribute.type {
                        result.addAttribute(NSAttributedString.Key.font, value: Font.semibold(presentationData.listsFontSize.baseDisplaySize), range: NSRange(location: attribute.range.lowerBound, length: attribute.range.count))
                    } else if case .italic = attribute.type {
                        result.addAttribute(NSAttributedString.Key.font, value: Font.semibold(15.0), range: NSRange(location: attribute.range.lowerBound, length: attribute.range.count))
                    }
                }
                attributedText = result
            } else {
                attributedText = parseMarkdownIntoAttributedString(
                    self.item.text,
                    attributes: MarkdownAttributes(
                        body: MarkdownAttributeSet(font: titleFont, textColor: titleColor),
                        bold: MarkdownAttributeSet(font: titleBoldFont, textColor: titleColor),
                        link: MarkdownAttributeSet(font: titleBoldFont, textColor: presentationData.theme.list.itemAccentColor),
                        linkAttribute: { value in return ("URL", value) }
                    )
                )
            }
            self.titleLabelNode.attributedText = attributedText
            self.titleLabelNode.linkHighlightColor = presentationData.theme.list.itemAccentColor.withMultipliedAlpha(0.5)
            self.titleLabelNode.highlightAttributeAction = { attributes in
                if let _ = attributes[NSAttributedString.Key(rawValue: "URL")] {
                    return NSAttributedString.Key(rawValue: "URL")
                } else {
                    return nil
                }
            }
            self.titleLabelNode.tapAttributeAction = { [weak item] attributes, _ in
                if let _ = attributes[NSAttributedString.Key(rawValue: "URL")] {
                    item?.textLinkAction()
                }
            }
        } else {
            self.titleLabelNode.attributedText = NSAttributedString(
                string: self.item.text,
                font: titleFont,
                textColor: titleColor)
        }
        
        self.titleLabelNode.isUserInteractionEnabled = self.titleLabelNode.tapAttributeAction != nil && self.item.action == nil
        
        self.subtitleNode.attributedText = subtitle
        
        var iconSize: CGSize?
        if let iconSource = self.item.iconSource {
            iconSize = iconSource.size
            self.iconNode.cornerRadius = iconSource.cornerRadius
            self.iconNode.contentMode = iconSource.contentMode
            self.iconNode.clipsToBounds = true
            if self.iconDisposable == nil {
                self.iconDisposable = (iconSource.signal |> deliverOnMainQueue).start(next: { [weak self] image in
                    guard let strongSelf = self else {
                        return
                    }
                    strongSelf.iconNode.image = image
                }).strict()
            }
        } else if let image = self.iconNode.image {
            iconSize = image.size
        } else if let animationName = self.item.animationName {
            if self.animationNode == nil {
                let animationNode = AnimationNode(animation: animationName, colors: ["__allcolors__": titleColor], scale: 1.0)
                animationNode.loop(count: 3)
                self.addSubnode(animationNode)
                self.animationNode = animationNode
            }
            iconSize = CGSize(width: 24.0, height: 24.0)
        } else {
            let iconImage = self.item.icon(presentationData.theme)
            self.iconNode.image = iconImage
            iconSize = iconImage?.size
        }
        
        if let iconAnimation = self.item.iconAnimation {
            let animatedIcon: ComponentView<Empty>
            if let current = self.animatedIcon {
                animatedIcon = current
            } else {
                animatedIcon = ComponentView()
                self.animatedIcon = animatedIcon
            }
            
            let animatedIconSize = CGSize(width: 24.0, height: 24.0)
            let _ = animatedIcon.update(
                transition: .immediate,
                component: AnyComponent(LottieComponent(
                    content: LottieComponent.AppBundleContent(name: iconAnimation.name),
                    color: titleColor,
                    startingPosition: iconAnimation.loop ? .begin : .end,
                    loop: iconAnimation.loop
                )),
                environment: {},
                containerSize: animatedIconSize
            )
            
            iconSize = animatedIconSize
        } else if let animatedIcon = self.animatedIcon {
            self.animatedIcon = nil
            animatedIcon.view?.removeFromSuperview()
        }
        
        let additionalIcon = self.item.additionalLeftIcon?(presentationData.theme)
        var additionalIconSize: CGSize?
        self.additionalIconNode.image = additionalIcon
        
        if let additionalIcon {
            additionalIconSize = additionalIcon.size
        }
        
        let badgeSize: CGSize?
        if let badge = self.item.badge {
            var badgeImage: UIImage?
            if let currentBadge = self.currentBadge, currentBadge.badge == badge {
                badgeImage = currentBadge.image
            } else {
                switch badge.style {
                case .badge:
                    let badgeTextColor: UIColor = presentationData.theme.list.itemCheckColors.foregroundColor
                    let badgeString = NSAttributedString(string: badge.value, font: Font.regular(13.0), textColor: badgeTextColor)
                    let badgeTextBounds = badgeString.boundingRect(with: CGSize(width: 100.0, height: 100.0), options: [.usesLineFragmentOrigin], context: nil)
                    
                    let badgeSideInset: CGFloat = 5.0
                    let badgeVerticalInset: CGFloat = 1.0
                    var badgeBackgroundSize = CGSize(width: badgeSideInset * 2.0 + ceil(badgeTextBounds.width), height: badgeVerticalInset * 2.0 + ceil(badgeTextBounds.height))
                    badgeBackgroundSize.width = max(badgeBackgroundSize.width, badgeBackgroundSize.height)
                    badgeImage = generateImage(badgeBackgroundSize, rotatedContext: { size, context in
                        context.clear(CGRect(origin: CGPoint(), size: size))
                        context.setFillColor(presentationData.theme.list.itemCheckColors.fillColor.cgColor)
                        context.addPath(UIBezierPath(roundedRect: CGRect(origin: CGPoint(), size: size), cornerRadius: size.height * 0.5).cgPath)
                        context.fillPath()
                        
                        UIGraphicsPushContext(context)
                        
                        badgeString.draw(at: CGPoint(x: badgeTextBounds.minX + floor((badgeBackgroundSize.width - badgeTextBounds.width) * 0.5), y: badgeTextBounds.minY + badgeVerticalInset))
                        
                        UIGraphicsPopContext()
                    })
                case .label:
                    let badgeTextColor: UIColor = presentationData.theme.list.itemCheckColors.foregroundColor
                    let badgeString = NSAttributedString(string: badge.value, font: Font.semibold(11.0), textColor: badgeTextColor)
                    let badgeTextBounds = badgeString.boundingRect(with: CGSize(width: 100.0, height: 100.0), options: [.usesLineFragmentOrigin], context: nil)
                    
                    let badgeSideInset: CGFloat = 3.0
                    let badgeVerticalInset: CGFloat = 1.0
                    let badgeBackgroundSize = CGSize(width: badgeSideInset * 2.0 + ceil(badgeTextBounds.width), height: badgeVerticalInset * 2.0 + ceil(badgeTextBounds.height))
                    badgeImage = generateImage(badgeBackgroundSize, rotatedContext: { size, context in
                        context.clear(CGRect(origin: CGPoint(), size: size))
                        context.setFillColor(presentationData.theme.list.itemCheckColors.fillColor.cgColor)
                        context.addPath(UIBezierPath(roundedRect: CGRect(origin: CGPoint(), size: size), cornerRadius: 5.0).cgPath)
                        context.fillPath()
                        
                        UIGraphicsPushContext(context)
                        
                        badgeString.draw(at: CGPoint(x: badgeTextBounds.minX + badgeSideInset + UIScreenPixel, y: badgeTextBounds.minY + badgeVerticalInset + UIScreenPixel))
                        
                        UIGraphicsPopContext()
                    })
                }
            }
            
            let badgeIconNode: ASImageNode
            if let current = self.badgeIconNode {
                badgeIconNode = current
            } else {
                badgeIconNode = ASImageNode()
                self.badgeIconNode = badgeIconNode
                self.addSubnode(badgeIconNode)
            }
            badgeIconNode.image = badgeImage
            
            badgeSize = badgeImage?.size
        } else {
            if let badgeIconNode = self.badgeIconNode {
                self.badgeIconNode = nil
                badgeIconNode.removeFromSupernode()
            }
            badgeSize = nil
        }
        
        var maxTextWidth: CGFloat = constrainedSize.width
        maxTextWidth -= sideInset
        
        if let iconSize = iconSize {
            maxTextWidth -= max(standardIconWidth, iconSize.width)
            maxTextWidth -= iconSpacing
        } else {
            maxTextWidth -= sideInset
        }
        
        if let badgeSize = badgeSize {
            maxTextWidth -= badgeSize.width
            maxTextWidth -= 8.0
        }
        
        maxTextWidth = max(1.0, maxTextWidth)
        
        let titleSize = self.titleLabelNode.updateLayout(CGSize(width: maxTextWidth, height: 1000.0))
        let subtitleSize = self.subtitleNode.updateLayout(CGSize(width: maxTextWidth, height: 1000.0))
        
        var minSize = CGSize()
        minSize.width += sideInset
        minSize.width += max(titleSize.width, subtitleSize.width)
        if let iconSize = iconSize {
            minSize.width += max(standardIconWidth, iconSize.width)
            minSize.width += iconSideInset
            minSize.width += iconSpacing
        } else {
            minSize.width += sideInset
        }
        if self.item.additionalLeftIcon != nil {
            minSize.width += 24.0
            minSize.width += iconSideInset
            minSize.width += iconSpacing
        }
        if let forcedHeight {
            minSize.height = forcedHeight
        } else {
            minSize.height += verticalInset * 2.0
            minSize.height += titleSize.height
            if subtitle != nil {
                minSize.height += titleSubtitleSpacing
                minSize.height += subtitleSize.height
            }
        }
        
        return (minSize: minSize, apply: { size, transition in
            var titleFrame = CGRect(origin: CGPoint(x: sideInset, y: verticalInset), size: titleSize)
            if let titleVerticalOffset {
                titleFrame = titleFrame.offsetBy(dx: 0.0, dy: titleVerticalOffset)
            }
            var subtitleFrame = CGRect(origin: CGPoint(x: sideInset, y: titleFrame.maxY + titleSubtitleSpacing), size: subtitleSize)
            if self.item.additionalLeftIcon != nil {
                titleFrame = titleFrame.offsetBy(dx: 26.0, dy: 0.0)
                subtitleFrame = subtitleFrame.offsetBy(dx: 26.0, dy: 0.0)
            } else if self.item.iconPosition == .left {
                titleFrame = titleFrame.offsetBy(dx: 36.0, dy: 0.0)
                subtitleFrame = subtitleFrame.offsetBy(dx: 36.0, dy: 0.0)
            }
            
            transition.updateFrame(node: self.highlightBackgroundNode, frame: CGRect(origin: CGPoint(), size: size), beginWithCurrentState: true)
            transition.updateFrameAdditive(node: self.titleLabelNode, frame: titleFrame)
            transition.updateFrameAdditive(node: self.subtitleNode, frame: subtitleFrame)
            
            if let badgeIconNode = self.badgeIconNode {
                if let iconSize = badgeIconNode.image?.size {
                    transition.updateFrame(node: badgeIconNode, frame: CGRect(origin: CGPoint(x: titleFrame.maxX + 8.0, y: titleFrame.minY + floor((titleFrame.height - iconSize.height) * 0.5)), size: iconSize))
                }
            }
            
            if let iconSize = iconSize {
                let iconWidth = max(standardIconWidth, iconSize.width)
                let iconFrame = CGRect(
                    origin: CGPoint(
                        x: self.item.iconPosition == .left ? iconSideInset : size.width - iconSideInset - iconWidth + floor((iconWidth - iconSize.width) / 2.0),
                        y: floor((size.height - iconSize.height) / 2.0)
                    ),
                    size: iconSize
                )
                transition.updateFrame(node: self.iconNode, frame: iconFrame, beginWithCurrentState: true)
                if let animationNode = self.animationNode {
                    transition.updateFrame(node: animationNode, frame: iconFrame, beginWithCurrentState: true)
                }
                if let animatedIconView = self.animatedIcon?.view {
                    if animatedIconView.superview == nil {
                        self.view.addSubview(animatedIconView)
                        animatedIconView.frame = iconFrame
                    } else {
                        transition.updateFrame(view: animatedIconView, frame: iconFrame, beginWithCurrentState: true)
                        if let currentAnimatedIconContent = self.currentAnimatedIconContent, currentAnimatedIconContent != self.item.iconAnimation {
                            if let animatedIconView = animatedIconView as? LottieComponent.View {
                                animatedIconView.playOnce()
                            }
                        }
                    }
                    
                    self.currentAnimatedIconContent = self.item.iconAnimation
                }
            }
            
            if let additionalIconSize {
                var iconFrame = CGRect(
                    origin: CGPoint(
                        x: 10.0,
                        y: floor((size.height - additionalIconSize.height) / 2.0)
                    ),
                    size: additionalIconSize
                )
                if self.item.iconPosition == .left {
                    iconFrame.origin.x = size.width - additionalIconSize.width - 10.0
                }
                transition.updateFrame(node: self.additionalIconNode, frame: iconFrame, beginWithCurrentState: true)
            }
        })
    }
}

private final class ContextControllerActionsListSeparatorItemNode: ASDisplayNode, ContextControllerActionsListItemNode {
    func canBeHighlighted() -> Bool {
        return false
    }
    
    func updateIsHighlighted(isHighlighted: Bool) {
    }
    
    func performAction() {
    }
    
    override init() {
        super.init()
    }
    
    func update(presentationData: PresentationData, constrainedSize: CGSize) -> (minSize: CGSize, apply: (_ size: CGSize, _ transition: ContainedViewLayoutTransition) -> Void) {
        return (minSize: CGSize(width: 0.0, height: 7.0), apply: { _, _ in
            self.backgroundColor = presentationData.theme.contextMenu.sectionSeparatorColor
        })
    }
}

private final class ContextControllerActionsListCustomItemNode: ASDisplayNode, ContextControllerActionsListItemNode {
    func canBeHighlighted() -> Bool {
        if let itemNode = self.itemNode {
            return itemNode.canBeHighlighted()
        } else {
            return false
        }
    }
    
    func updateIsHighlighted(isHighlighted: Bool) {
        if let itemNode = self.itemNode {
            itemNode.updateIsHighlighted(isHighlighted: isHighlighted)
        }
    }
    
    func performAction() {
        if let itemNode = self.itemNode {
            itemNode.performAction()
        }
    }
    
    private let getController: () -> ContextControllerProtocol?
    private let item: ContextMenuCustomItem
    private let requestDismiss: (ContextMenuActionResult) -> Void
    
    private var presentationData: PresentationData?
    private(set) var itemNode: ContextMenuCustomNode?
    
    init(
        getController: @escaping () -> ContextControllerProtocol?,
        item: ContextMenuCustomItem,
        requestDismiss: @escaping (ContextMenuActionResult) -> Void
    ) {
        self.getController = getController
        self.item = item
        self.requestDismiss = requestDismiss
        
        super.init()
    }
    
    func update(presentationData: PresentationData, constrainedSize: CGSize) -> (minSize: CGSize, apply: (_ size: CGSize, _ transition: ContainedViewLayoutTransition) -> Void) {
        if self.presentationData?.theme !== presentationData.theme {
            if let itemNode = self.itemNode {
                itemNode.updateTheme(presentationData: presentationData)
            }
        }
        self.presentationData = presentationData
        
        let itemNode: ContextMenuCustomNode
        if let current = self.itemNode {
            itemNode = current
        } else {
            itemNode = self.item.node(
                presentationData: presentationData,
                getController: self.getController,
                actionSelected: { result in
                    switch result {
                    case .dismissWithoutContent:
                        self.requestDismiss(result)
                    default:
                        break
                    }
                }
            )
            self.itemNode = itemNode
            self.addSubnode(itemNode)
        }
        
        let itemLayoutAndApply = itemNode.updateLayout(constrainedWidth: constrainedSize.width, constrainedHeight: constrainedSize.height)
        
        return (minSize: itemLayoutAndApply.0, apply: { size, transition in
            transition.updateFrame(node: itemNode, frame: CGRect(origin: CGPoint(), size: size), beginWithCurrentState: true)
            itemLayoutAndApply.1(size, transition)
        })
    }
}

public final class ContextControllerActionsListStackItem: ContextControllerActionsStackItem {
    final class Node: ASDisplayNode, ContextControllerActionsStackItemNode {
        private final class Item {
            let node: ContextControllerActionsListItemNode
            let separatorNode: ASDisplayNode?
            
            init(node: ContextControllerActionsListItemNode, separatorNode: ASDisplayNode?) {
                self.node = node
                self.separatorNode = separatorNode
            }
        }
        
        private let context: AccountContext?
        private let requestUpdate: (ContainedViewLayoutTransition) -> Void
        private let getController: () -> ContextControllerProtocol?
        private let requestDismiss: (ContextMenuActionResult) -> Void
        private var items: [ContextMenuItem]
        private var itemNodes: [Item]
        
        private var hapticFeedback: HapticFeedback?
        private var highlightedItemNode: Item?
        
        private var invalidatedItemNodes: Bool = false
        
        var wantsFullWidth: Bool {
            return false
        }
        
        init(
            context: AccountContext?,
            getController: @escaping () -> ContextControllerProtocol?,
            requestDismiss: @escaping (ContextMenuActionResult) -> Void,
            requestUpdate: @escaping (ContainedViewLayoutTransition) -> Void,
            items: [ContextMenuItem]
        ) {
            self.context = context
            self.requestUpdate = requestUpdate
            self.getController = getController
            self.requestDismiss = requestDismiss
            self.items = items
            
            var requestUpdateAction: ((AnyHashable, ContextMenuActionItem) -> Void)?
            self.itemNodes = items.map { item -> Item in
                switch item {
                case let .action(actionItem):
                    return Item(
                        node: ContextControllerActionsListActionItemNode(
                            context: context,
                            getController: getController,
                            requestDismiss: requestDismiss,
                            requestUpdateAction: { id, action in
                                requestUpdateAction?(id, action)
                            },
                            item: actionItem
                        ),
                        separatorNode: ASDisplayNode()
                    )
                case .separator:
                    return Item(
                        node: ContextControllerActionsListSeparatorItemNode(),
                        separatorNode: nil
                    )
                case let .custom(customItem, _):
                    return Item(
                        node: ContextControllerActionsListCustomItemNode(
                            getController: getController,
                            item: customItem,
                            requestDismiss: requestDismiss
                        ),
                        separatorNode: ASDisplayNode()
                    )
                }
            }
            
            super.init()
            
            for item in self.itemNodes {
                if let separatorNode = item.separatorNode {
                    self.addSubnode(separatorNode)
                }
            }
            for item in self.itemNodes {
                self.addSubnode(item.node)
            }
            
            requestUpdateAction = { [weak self] id, action in
                guard let self else {
                    return
                }
                self.requestUpdateAction(id: id, action: action)
            }
        }
        
        func updateItems(items: [ContextMenuItem]) {
            self.items = items
            for i in 0 ..< items.count {
                if self.itemNodes.count < i {
                    break
                }
                if case let .action(action) = items[i] {
                    if let itemNode = self.itemNodes[i].node as? ContextControllerActionsListActionItemNode {
                        itemNode.setItem(item: action)
                    }
                }
            }
        }
        
        private func requestUpdateAction(id: AnyHashable, action: ContextMenuActionItem) {
            loop: for i in 0 ..< self.items.count {
                switch self.items[i] {
                case let .action(currentAction):
                    if currentAction.id == id {
                        let previousNode = self.itemNodes[i]
                        previousNode.node.removeFromSupernode()
                        previousNode.separatorNode?.removeFromSupernode()
                        
                        let addedNode = Item(
                            node: ContextControllerActionsListActionItemNode(
                                context: self.context,
                                getController: self.getController,
                                requestDismiss: self.requestDismiss,
                                requestUpdateAction: { [weak self] id, action in
                                    guard let self else {
                                        return
                                    }
                                    self.requestUpdateAction(id: id, action: action)
                                },
                                item: action
                            ),
                            separatorNode: ASDisplayNode()
                        )
                        self.itemNodes[i] = addedNode
                        if let separatorNode = addedNode.separatorNode {
                            self.insertSubnode(separatorNode, at: 0)
                        }
                        self.addSubnode(addedNode.node)
                        
                        self.requestUpdate(.immediate)
                        
                        break loop
                    }
                default:
                    break
                }
            }
        }
        
        func update(
            presentationData: PresentationData,
            constrainedSize: CGSize,
            standardMinWidth: CGFloat,
            standardMaxWidth: CGFloat,
            additionalBottomInset: CGFloat,
            transition: ContainedViewLayoutTransition
        ) -> (size: CGSize, apparentHeight: CGFloat) {
            var itemNodeLayouts: [(minSize: CGSize, apply: (_ size: CGSize, _ transition: ContainedViewLayoutTransition) -> Void)] = []
            var combinedSize = CGSize()
            for item in self.itemNodes {
                item.separatorNode?.backgroundColor = presentationData.theme.contextMenu.itemSeparatorColor
                
                let itemNodeLayout = item.node.update(
                    presentationData: presentationData,
                    constrainedSize: CGSize(width: standardMaxWidth, height: constrainedSize.height)
                )
                itemNodeLayouts.append(itemNodeLayout)
                combinedSize.width = max(combinedSize.width, itemNodeLayout.minSize.width)
                combinedSize.height += itemNodeLayout.minSize.height
            }
            self.invalidatedItemNodes = false
            combinedSize.width = max(combinedSize.width, standardMinWidth)
            
            var nextItemOrigin = CGPoint()
            for i in 0 ..< self.itemNodes.count {
                let item = self.itemNodes[i]
                let itemNodeLayout = itemNodeLayouts[i]
                
                var itemTransition = transition
                if item.node.frame.isEmpty {
                    itemTransition = .immediate
                }
                
                let itemSize = CGSize(width: combinedSize.width, height: itemNodeLayout.minSize.height)
                let itemFrame = CGRect(origin: nextItemOrigin, size: itemSize)
                itemTransition.updateFrame(node: item.node, frame: itemFrame, beginWithCurrentState: true)
                
                if let separatorNode = item.separatorNode {
                    itemTransition.updateFrame(node: separatorNode, frame: CGRect(origin: CGPoint(x: itemFrame.minX, y: itemFrame.maxY), size: CGSize(width: itemFrame.width, height: UIScreenPixel)), beginWithCurrentState: true)
                    
                    var separatorHidden = false
                    if i != self.itemNodes.count - 1 {
                        switch self.items[i + 1] {
                        case .separator:
                            separatorHidden = true
                        case .action:
                            separatorHidden = false
                        case .custom:
                            separatorHidden = false
                        }
                    } else {
                        separatorHidden = true
                    }
                    
                    if let itemContainerNode = item.node as? ContextControllerActionsListCustomItemNode, let itemNode = itemContainerNode.itemNode {
                        if !itemNode.needsSeparator {
                            separatorHidden = true
                        }
                    }
                    
                    separatorNode.isHidden = separatorHidden
                }
                
                itemNodeLayout.apply(itemSize, itemTransition)
                nextItemOrigin.y += itemSize.height
            }
            
            return (combinedSize, combinedSize.height)
        }
        
        func highlightGestureMoved(location: CGPoint) {
            var highlightedItemNode: Item?
            for itemNode in self.itemNodes {
                if itemNode.node.frame.contains(location) {
                    if itemNode.node.canBeHighlighted() {
                        highlightedItemNode = itemNode
                    }
                    break
                }
            }
            if self.highlightedItemNode !== highlightedItemNode {
                self.highlightedItemNode?.node.updateIsHighlighted(isHighlighted: false)
                highlightedItemNode?.node.updateIsHighlighted(isHighlighted: true)
                
                self.highlightedItemNode = highlightedItemNode
                if self.hapticFeedback == nil {
                    self.hapticFeedback = HapticFeedback()
                }
                self.hapticFeedback?.tap()
            }
        }
        
        func highlightGestureFinished(performAction: Bool) {
            if let highlightedItemNode = self.highlightedItemNode {
                self.highlightedItemNode = nil
                highlightedItemNode.node.updateIsHighlighted(isHighlighted: false)
                if performAction {
                    highlightedItemNode.node.performAction()
                }
            }
        }
        
        func decreaseHighlightedIndex() {
            let previousHighlightedItemNode: Item? = self.highlightedItemNode
            if let highlightedItemNode = self.highlightedItemNode, let index = self.itemNodes.firstIndex(where: { $0 === highlightedItemNode }) {
                self.highlightedItemNode = self.itemNodes[max(0, index - 1)]
            } else {
                self.highlightedItemNode = self.itemNodes.first
            }
            
            if previousHighlightedItemNode !== self.highlightedItemNode {
                previousHighlightedItemNode?.node.updateIsHighlighted(isHighlighted: false)
                self.highlightedItemNode?.node.updateIsHighlighted(isHighlighted: true)
            }
        }
        
        func increaseHighlightedIndex() {
            let previousHighlightedItemNode: Item? = self.highlightedItemNode
            if let highlightedItemNode = self.highlightedItemNode, let index = self.itemNodes.firstIndex(where: { $0 === highlightedItemNode }) {
                self.highlightedItemNode = self.itemNodes[min(self.itemNodes.count - 1, index + 1)]
            } else {
                self.highlightedItemNode = self.itemNodes.first
            }
            
            if previousHighlightedItemNode !== self.highlightedItemNode {
                previousHighlightedItemNode?.node.updateIsHighlighted(isHighlighted: false)
                self.highlightedItemNode?.node.updateIsHighlighted(isHighlighted: true)
            }
        }
    }
    
    public let id: AnyHashable?
    public let items: [ContextMenuItem]
    public let reactionItems: ContextControllerReactionItems?
    public let previewReaction: ContextControllerPreviewReaction?
    public let tip: ContextController.Tip?
    public let tipSignal: Signal<ContextController.Tip?, NoError>?
    public let dismissed: (() -> Void)?
    
    public init(
        id: AnyHashable?,
        items: [ContextMenuItem],
        reactionItems: ContextControllerReactionItems?,
        previewReaction: ContextControllerPreviewReaction?,
        tip: ContextController.Tip?,
        tipSignal: Signal<ContextController.Tip?, NoError>?,
        dismissed: (() -> Void)?
    ) {
        self.id = id
        self.items = items
        self.reactionItems = reactionItems
        self.previewReaction = previewReaction
        self.tip = tip
        self.tipSignal = tipSignal
        self.dismissed = dismissed
    }
    
    public func node(
        context: AccountContext?,
        getController: @escaping () -> ContextControllerProtocol?,
        requestDismiss: @escaping (ContextMenuActionResult) -> Void,
        requestUpdate: @escaping (ContainedViewLayoutTransition) -> Void,
        requestUpdateApparentHeight: @escaping (ContainedViewLayoutTransition) -> Void
    ) -> ContextControllerActionsStackItemNode {
        return Node(
            context: context,
            getController: getController,
            requestDismiss: requestDismiss,
            requestUpdate: requestUpdate,
            items: self.items
        )
    }
}

final class ContextControllerActionsCustomStackItem: ContextControllerActionsStackItem {
    private final class Node: ASDisplayNode, ContextControllerActionsStackItemNode {
        private let requestUpdate: (ContainedViewLayoutTransition) -> Void
        private let contentNode: ContextControllerItemsNode
        
        init(
            content: ContextControllerItemsContent,
            getController: @escaping () -> ContextControllerProtocol?,
            requestUpdate: @escaping (ContainedViewLayoutTransition) -> Void,
            requestUpdateApparentHeight: @escaping (ContainedViewLayoutTransition) -> Void
        ) {
            self.requestUpdate = requestUpdate
            self.contentNode = content.node(requestUpdate: { transition in
                requestUpdate(transition)
            }, requestUpdateApparentHeight: { transition in
                requestUpdateApparentHeight(transition)
            })
            
            super.init()
            
            self.addSubnode(self.contentNode)
        }
        
        var wantsFullWidth: Bool {
            return true
        }
        
        func update(
            presentationData: PresentationData,
            constrainedSize: CGSize,
            standardMinWidth: CGFloat,
            standardMaxWidth: CGFloat,
            additionalBottomInset: CGFloat,
            transition: ContainedViewLayoutTransition
        ) -> (size: CGSize, apparentHeight: CGFloat) {
            let contentLayout = self.contentNode.update(
                presentationData: presentationData,
                constrainedWidth: constrainedSize.width,
                maxHeight: constrainedSize.height,
                bottomInset: additionalBottomInset,
                transition: transition
            )
            transition.updateFrame(node: self.contentNode, frame: CGRect(origin: CGPoint(), size: contentLayout.cleanSize), beginWithCurrentState: true)
            
            return (contentLayout.cleanSize, contentLayout.apparentHeight)
        }
        
        func highlightGestureMoved(location: CGPoint) {
        }
        
        func highlightGestureFinished(performAction: Bool) {
        }
        
        func decreaseHighlightedIndex() {
        }
        
        func increaseHighlightedIndex() {
        }
    }
    
    let id: AnyHashable?
    private let content: ContextControllerItemsContent
    let reactionItems: ContextControllerReactionItems?
    let previewReaction: ContextControllerPreviewReaction?
    let tip: ContextController.Tip?
    let tipSignal: Signal<ContextController.Tip?, NoError>?
    let dismissed: (() -> Void)?
    
    init(
        id: AnyHashable?,
        content: ContextControllerItemsContent,
        reactionItems: ContextControllerReactionItems?,
        previewReaction: ContextControllerPreviewReaction?,
        tip: ContextController.Tip?,
        tipSignal: Signal<ContextController.Tip?, NoError>?,
        dismissed: (() -> Void)?
    ) {
        self.id = id
        self.content = content
        self.reactionItems = reactionItems
        self.previewReaction = previewReaction
        self.tip = tip
        self.tipSignal = tipSignal
        self.dismissed = dismissed
    }
    
    func node(
        context: AccountContext?,
        getController: @escaping () -> ContextControllerProtocol?,
        requestDismiss: @escaping (ContextMenuActionResult) -> Void,
        requestUpdate: @escaping (ContainedViewLayoutTransition) -> Void,
        requestUpdateApparentHeight: @escaping (ContainedViewLayoutTransition) -> Void
    ) -> ContextControllerActionsStackItemNode {
        return Node(
            content: self.content,
            getController: getController,
            requestUpdate: requestUpdate,
            requestUpdateApparentHeight: requestUpdateApparentHeight
        )
    }
}

func makeContextControllerActionsStackItem(items: ContextController.Items) -> [ContextControllerActionsStackItem] {
    var reactionItems: ContextControllerReactionItems?
    if let context = items.context, let animationCache = items.animationCache, !items.reactionItems.isEmpty {
        reactionItems = ContextControllerReactionItems(
            context: context,
            reactionItems: items.reactionItems,
            selectedReactionItems: items.selectedReactionItems,
            reactionsTitle: items.reactionsTitle,
            reactionsLocked: items.reactionsLocked,
            animationCache: animationCache,
            alwaysAllowPremiumReactions: items.alwaysAllowPremiumReactions,
            allPresetReactionsAreAvailable: items.allPresetReactionsAreAvailable,
            getEmojiContent: items.getEmojiContent
        )
    }
    var previewReaction: ContextControllerPreviewReaction?
    if let context = items.context, let file = items.previewReaction {
        previewReaction = ContextControllerPreviewReaction(context: context, file: file)
    }
    switch items.content {
    case let .list(listItems):
        return [ContextControllerActionsListStackItem(id: items.id, items: listItems, reactionItems: reactionItems, previewReaction: previewReaction, tip: items.tip, tipSignal: items.tipSignal, dismissed: items.dismissed)]
    case let .twoLists(listItems1, listItems2):
        return [ContextControllerActionsListStackItem(id: items.id, items: listItems1, reactionItems: nil, previewReaction: nil, tip: nil, tipSignal: nil, dismissed: items.dismissed), ContextControllerActionsListStackItem(id: nil, items: listItems2, reactionItems: nil, previewReaction: nil, tip: nil, tipSignal: nil, dismissed: nil)]
    case let .custom(customContent):
        return [ContextControllerActionsCustomStackItem(id: items.id, content: customContent, reactionItems: reactionItems, previewReaction: previewReaction, tip: items.tip, tipSignal: items.tipSignal, dismissed: items.dismissed)]
    }
}

public final class ContextControllerActionsStackNode: ASDisplayNode {
    public enum Presentation {
        case modal
        case inline
        case additional
    }
    
    final class NavigationContainer: ASDisplayNode, ASGestureRecognizerDelegate {
        let backgroundNode: NavigationBackgroundNode
        let parentShadowNode: ASImageNode
        
        var requestUpdate: ((ContainedViewLayoutTransition) -> Void)?
        var requestPop: (() -> Void)?
        var transitionFraction: CGFloat = 0.0
        
        private var panRecognizer: InteractiveTransitionGestureRecognizer?
        
        var isNavigationEnabled: Bool = false {
            didSet {
                self.panRecognizer?.isEnabled = self.isNavigationEnabled
            }
        }
        
        override init() {
            self.backgroundNode = NavigationBackgroundNode(color: .clear, enableBlur: false)
            self.parentShadowNode = ASImageNode()
            self.parentShadowNode.image = UIImage(bundleImageName: "Components/Context Menu/Shadow")?.stretchableImage(withLeftCapWidth: 60, topCapHeight: 48)
            
            super.init()
            
            self.addSubnode(self.backgroundNode)
            
            self.clipsToBounds = true
            self.cornerRadius = 14.0
            
            let panRecognizer = InteractiveTransitionGestureRecognizer(target: self, action: #selector(self.panGesture(_:)), allowedDirections: { [weak self] point in
                guard let strongSelf = self else {
                    return []
                }
                let _ = strongSelf
                return [.right]
            })
            panRecognizer.delegate = self.wrappedGestureRecognizerDelegate
            self.view.addGestureRecognizer(panRecognizer)
            self.panRecognizer = panRecognizer
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return false
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            if let _ = otherGestureRecognizer as? InteractiveTransitionGestureRecognizer {
                return false
            }
            if let _ = otherGestureRecognizer as? UIPanGestureRecognizer {
                return true
            }
            return false
        }
        
        @objc private func panGesture(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                self.transitionFraction = 0.0
            case .changed:
                let distanceFactor: CGFloat = recognizer.translation(in: self.view).x / self.bounds.width
                let transitionFraction = max(0.0, min(1.0, distanceFactor))
                if self.transitionFraction != transitionFraction {
                    self.transitionFraction = transitionFraction
                    self.requestUpdate?(.immediate)
                }
            case .ended, .cancelled:
                let distanceFactor: CGFloat = recognizer.translation(in: self.view).x / self.bounds.width
                let transitionFraction = max(0.0, min(1.0, distanceFactor))
                if transitionFraction > 0.2 {
                    self.transitionFraction = 0.0
                    self.requestPop?()
                } else {
                    self.transitionFraction = 0.0
                    self.requestUpdate?(.animated(duration: 0.45, curve: .spring))
                }
            default:
                break
            }
        }
        
        func update(presentationData: PresentationData, presentation: Presentation, size: CGSize, transition: ContainedViewLayoutTransition) {
            switch presentation {
            case .modal:
                self.backgroundNode.updateColor(color: presentationData.theme.contextMenu.backgroundColor, enableBlur: false, forceKeepBlur: false, transition: transition)
                self.parentShadowNode.isHidden = true
            case .inline:
                self.backgroundNode.updateColor(color: presentationData.theme.contextMenu.backgroundColor, enableBlur: true, forceKeepBlur: true, transition: transition)
                self.parentShadowNode.isHidden = false
            case .additional:
                self.backgroundNode.updateColor(color: presentationData.theme.contextMenu.backgroundColor.withMultipliedAlpha(0.5), enableBlur: true, forceKeepBlur: true, transition: transition)
                self.parentShadowNode.isHidden = false
            }
            self.backgroundNode.update(size: size, transition: transition)
        }
    }
    
    final class ItemContainer: ASDisplayNode {
        let getController: () -> ContextControllerProtocol?
        let requestUpdate: (ContainedViewLayoutTransition) -> Void
        let item: ContextControllerActionsStackItem
        let node: ContextControllerActionsStackItemNode
        let dimNode: ASDisplayNode
        var tip: ContextController.Tip?
        let tipSignal: Signal<ContextController.Tip?, NoError>?
        var tipNode: InnerTextSelectionTipContainerNode?
        let reactionItems: ContextControllerReactionItems?
        let previewReaction: ContextControllerPreviewReaction?
        let itemDismissed: (() -> Void)?
        var storedScrollingState: CGFloat?
        let positionLock: CGFloat?
        
        private var tipDisposable: Disposable?
        
        init(
            context: AccountContext?,
            getController: @escaping () -> ContextControllerProtocol?,
            requestDismiss: @escaping (ContextMenuActionResult) -> Void,
            requestUpdate: @escaping (ContainedViewLayoutTransition) -> Void,
            requestUpdateApparentHeight: @escaping (ContainedViewLayoutTransition) -> Void,
            item: ContextControllerActionsStackItem,
            tip: ContextController.Tip?,
            tipSignal: Signal<ContextController.Tip?, NoError>?,
            reactionItems: ContextControllerReactionItems?,
            previewReaction: ContextControllerPreviewReaction?,
            itemDismissed: (() -> Void)?,
            positionLock: CGFloat?
        ) {
            self.getController = getController
            self.requestUpdate = requestUpdate
            self.item = item
            self.node = item.node(
                context: context,
                getController: getController,
                requestDismiss: requestDismiss,
                requestUpdate: requestUpdate,
                requestUpdateApparentHeight: requestUpdateApparentHeight
            )
            
            self.dimNode = ASDisplayNode()
            self.dimNode.isUserInteractionEnabled = false
            self.dimNode.alpha = 0.0
            
            self.reactionItems = reactionItems
            self.previewReaction = previewReaction
            self.itemDismissed = itemDismissed
            self.positionLock = positionLock
            
            self.tip = tip
            self.tipSignal = tipSignal
            
            super.init()
            
            self.clipsToBounds = true
            
            self.addSubnode(self.node)
            self.addSubnode(self.dimNode)
            
            if let tipSignal = tipSignal {
                self.tipDisposable = (tipSignal
                |> deliverOnMainQueue).start(next: { [weak self] tip in
                    guard let strongSelf = self else {
                        return
                    }
                    strongSelf.tip = tip
                    requestUpdate(.immediate)
                }).strict()
            }
        }
        
        deinit {
            self.tipDisposable?.dispose()
        }
        
        func update(
            presentationData: PresentationData,
            constrainedSize: CGSize,
            standardMinWidth: CGFloat,
            standardMaxWidth: CGFloat,
            additionalBottomInset: CGFloat,
            transitionFraction: CGFloat,
            transition: ContainedViewLayoutTransition
        ) -> (size: CGSize, apparentHeight: CGFloat) {
            let (size, apparentHeight) = self.node.update(
                presentationData: presentationData,
                constrainedSize: constrainedSize,
                standardMinWidth: standardMinWidth,
                standardMaxWidth: standardMaxWidth,
                additionalBottomInset: additionalBottomInset,
                transition: transition
            )
            
            let maxScaleOffset: CGFloat = 10.0
            let scaleOffset: CGFloat = 0.0 * transitionFraction + maxScaleOffset * (1.0 - transitionFraction)
            let scale: CGFloat = (size.width - scaleOffset) / size.width
            let yOffset: CGFloat = size.height * (1.0 - scale)
            let transitionOffset = (1.0 - transitionFraction) * size.width / 2.0
            transition.updatePosition(node: self.node, position: CGPoint(x: size.width / 2.0 + scaleOffset / 2.0 + transitionOffset, y: size.height / 2.0 - yOffset / 2.0), beginWithCurrentState: true)
            transition.updateBounds(node: self.node, bounds: CGRect(origin: CGPoint(), size: size), beginWithCurrentState: true)
            transition.updateTransformScale(node: self.node, scale: scale, beginWithCurrentState: true)
            
            return (size, apparentHeight)
        }
        
        func updateTip(presentationData: PresentationData, presentation: ContextControllerActionsStackNode.Presentation, width: CGFloat, transition: ContainedViewLayoutTransition) -> (node: InnerTextSelectionTipContainerNode, height: CGFloat)? {
            if let tip = self.tip {
                var updatedTransition = transition
                if let tipNode = self.tipNode, tipNode.tip == tip {
                } else {
                    let previousTipNode = self.tipNode
                    updatedTransition = .immediate
                    let tipNode = InnerTextSelectionTipContainerNode(presentationData: presentationData, tip: tip)
                    tipNode.requestDismiss = { [weak self] completion in
                        self?.getController()?.dismiss(completion: completion)
                    }
                    self.tipNode = tipNode
                    
                    if let previousTipNode = previousTipNode {
                        previousTipNode.animateTransitionInside(other: tipNode)
                        previousTipNode.removeFromSupernode()
                        
                        tipNode.animateContentIn()
                    }
                }
                
                if let tipNode = self.tipNode {
                    let size = tipNode.updateLayout(widthClass: .compact, presentation: presentation, width: width, transition: updatedTransition)
                    return (tipNode, size.height)
                } else {
                    return nil
                }
            } else {
                return nil
            }
        }
        
        func updateDimNode(presentationData: PresentationData, size: CGSize, transitionFraction: CGFloat, transition: ContainedViewLayoutTransition) {
            self.dimNode.backgroundColor = presentationData.theme.contextMenu.sectionSeparatorColor
            
            transition.updateFrame(node: self.dimNode, frame: CGRect(origin: CGPoint(), size: size), beginWithCurrentState: true)
            transition.updateAlpha(node: self.dimNode, alpha: 1.0 - transitionFraction, beginWithCurrentState: true)
        }
        
        func highlightGestureMoved(location: CGPoint) {
            if let tipNode = self.tipNode {
                let tipLocation = self.view.convert(location, to: tipNode.view)
                tipNode.highlightGestureMoved(location: tipLocation)
            }
            self.node.highlightGestureMoved(location: self.view.convert(location, to: self.node.view))
        }
        
        func highlightGestureFinished(performAction: Bool) {
            if let tipNode = self.tipNode {
                tipNode.highlightGestureFinished(performAction: performAction)
            }
            self.node.highlightGestureFinished(performAction: performAction)
        }
        
        func decreaseHighlightedIndex() {
            self.node.decreaseHighlightedIndex()
        }
        
        func increaseHighlightedIndex() {
            self.node.increaseHighlightedIndex()
        }
    }
    
    private let context: AccountContext?
    private let getController: () -> ContextControllerProtocol?
    private let requestDismiss: (ContextMenuActionResult) -> Void
    private let requestUpdate: (ContainedViewLayoutTransition) -> Void
    
    private let navigationContainer: NavigationContainer
    private var itemContainers: [ItemContainer] = []
    private var dismissingItemContainers: [(container: ItemContainer, isPopped: Bool)] = []
    
    private var selectionPanGesture: UIPanGestureRecognizer?
    
    public var topReactionItems: ContextControllerReactionItems? {
        return self.itemContainers.last?.reactionItems
    }
    
    public var topPreviewReaction: ContextControllerPreviewReaction? {
        return self.itemContainers.last?.previewReaction
    }
    
    public var topPositionLock: CGFloat? {
        return self.itemContainers.last?.positionLock
    }
    
    public var storedScrollingState: CGFloat? {
        return self.itemContainers.last?.storedScrollingState
    }
    
    public init(
        context: AccountContext?,
        getController: @escaping () -> ContextControllerProtocol?,
        requestDismiss: @escaping (ContextMenuActionResult) -> Void,
        requestUpdate: @escaping (ContainedViewLayoutTransition) -> Void
    ) {
        self.context = context
        self.getController = getController
        self.requestDismiss = requestDismiss
        self.requestUpdate = requestUpdate
        
        self.navigationContainer = NavigationContainer()
        
        super.init()
        
        self.addSubnode(self.navigationContainer.parentShadowNode)
        self.addSubnode(self.navigationContainer)
        
        self.navigationContainer.requestUpdate = { [weak self] transition in
            guard let strongSelf = self else {
                return
            }
            strongSelf.requestUpdate(transition)
        }
        
        self.navigationContainer.requestPop = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.pop()
        }
        
        let selectionPanGesture = UIPanGestureRecognizer(target: self, action: #selector(self.panGesture(_:)))
        self.selectionPanGesture = selectionPanGesture
        self.view.addGestureRecognizer(selectionPanGesture)
        selectionPanGesture.isEnabled = false
    }
    
    @objc private func panGesture(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .changed:
            let location = recognizer.location(in: self.view)
            self.highlightGestureMoved(location: location)
        case .ended:
            self.highlightGestureFinished(performAction: true)
        case .cancelled:
            self.highlightGestureFinished(performAction: false)
        default:
            break
        }
    }
    
    public func replace(item: ContextControllerActionsStackItem, animated: Bool?) {
        if let item = item as? ContextControllerActionsListStackItem, let topContainer = self.itemContainers.first, let topItem = topContainer.item as? ContextControllerActionsListStackItem, let topId = topItem.id, let id = item.id, topId == id, item.items.count == topItem.items.count {
            if let topNode = topContainer.node as? ContextControllerActionsListStackItem.Node {
                var matches = true
                for i in 0 ..< item.items.count {
                    switch item.items[i] {
                    case .action:
                        if case .action = topItem.items[i] {
                        } else {
                            matches = false
                        }
                    case .custom:
                        if case .custom = topItem.items[i] {
                        } else {
                            matches = false
                        }
                    case .separator:
                        if case .separator = topItem.items[i] {
                        } else {
                            matches = false
                        }
                    }
                }
                
                if matches {
                    topNode.updateItems(items: item.items)
                    self.requestUpdate(.animated(duration: 0.3, curve: .spring))
                    return
                }
            }
        }
        
        var resolvedAnimated = false
        if let animated {
            resolvedAnimated = animated
        } else {
            if let id = item.id, let lastId = self.itemContainers.last?.item.id {
                if id != lastId {
                    resolvedAnimated = true
                }
            }
        }
        
        for itemContainer in self.itemContainers {
            if resolvedAnimated {
                self.dismissingItemContainers.append((itemContainer, false))
            } else {
                itemContainer.tipNode?.removeFromSupernode()
                itemContainer.removeFromSupernode()
            }
        }
        self.itemContainers.removeAll()
        self.navigationContainer.isNavigationEnabled = self.itemContainers.count > 1
        
        self.push(item: item, currentScrollingState: nil, positionLock: nil, animated: resolvedAnimated)
    }
    
    public func push(item: ContextControllerActionsStackItem, currentScrollingState: CGFloat?, positionLock: CGFloat?, animated: Bool) {
        if let itemContainer = self.itemContainers.last {
            itemContainer.storedScrollingState = currentScrollingState
        }
        let itemContainer = ItemContainer(
            context: self.context,
            getController: self.getController,
            requestDismiss: self.requestDismiss,
            requestUpdate: self.requestUpdate,
            requestUpdateApparentHeight: { [weak self] transition in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.requestUpdate(transition)
            },
            item: item,
            tip: item.tip,
            tipSignal: item.tipSignal,
            reactionItems: item.reactionItems,
            previewReaction: item.previewReaction,
            itemDismissed: item.dismissed,
            positionLock: positionLock
        )
        self.itemContainers.append(itemContainer)
        self.navigationContainer.addSubnode(itemContainer)
        self.navigationContainer.isNavigationEnabled = self.itemContainers.count > 1
        
        let transition: ContainedViewLayoutTransition
        if animated {
            transition = .animated(duration: self.itemContainers.count == 1 ? 0.3 : 0.45, curve: .spring)
        } else {
            transition = .immediate
        }
        self.requestUpdate(transition)
    }
    
    public func clearStoredScrollingState() {
        self.itemContainers.last?.storedScrollingState = nil
    }
    
    public func pop() {
        if self.itemContainers.count == 1 {
            //dismiss
        } else {
            let itemContainer = self.itemContainers[self.itemContainers.count - 1]
            self.itemContainers.remove(at: self.itemContainers.count - 1)
            self.dismissingItemContainers.append((itemContainer, true))
            
            itemContainer.itemDismissed?()
        }
        
        self.navigationContainer.isNavigationEnabled = self.itemContainers.count > 1
        
        let transition: ContainedViewLayoutTransition = .animated(duration: 0.45, curve: .spring)
        self.requestUpdate(transition)
    }
    
    public func update(
        presentationData: PresentationData,
        constrainedSize: CGSize,
        presentation: Presentation,
        transition: ContainedViewLayoutTransition
    ) -> CGSize {
        let tipSpacing: CGFloat = 10.0
        
        let animateAppearingContainers = transition.isAnimated && !self.dismissingItemContainers.isEmpty
        
        struct TipLayout {
            var tipNode: InnerTextSelectionTipContainerNode
            var tipHeight: CGFloat
        }
        
        struct ItemLayout {
            var size: CGSize
            var apparentHeight: CGFloat
            var transitionFraction: CGFloat
            var alphaTransitionFraction: CGFloat
            var itemTransition: ContainedViewLayoutTransition
            var animateAppearingContainer: Bool
            var tip: TipLayout?
        }
        
        var topItemSize = CGSize()
        var itemLayouts: [ItemLayout] = []
        for i in 0 ..< self.itemContainers.count {
            let itemContainer = self.itemContainers[i]
            
            var animateAppearingContainer = false
            var itemContainerTransition = transition
            if itemContainer.bounds.isEmpty {
                itemContainerTransition = .immediate
                animateAppearingContainer = i == self.itemContainers.count - 1 && animateAppearingContainers || self.itemContainers.count > 1
            }
            
            let itemConstrainedHeight: CGFloat = constrainedSize.height
            
            let transitionFraction: CGFloat
            let alphaTransitionFraction: CGFloat
            if i == self.itemContainers.count - 1 {
                transitionFraction = self.navigationContainer.transitionFraction
                alphaTransitionFraction = 1.0
            } else if i == self.itemContainers.count - 2 {
                transitionFraction = self.navigationContainer.transitionFraction - 1.0
                alphaTransitionFraction = self.navigationContainer.transitionFraction
            } else {
                transitionFraction = 0.0
                alphaTransitionFraction = 0.0
            }
            
            var tip: TipLayout?
            
            let itemContainerConstrainedSize: CGSize
            let standardMinWidth: CGFloat
            let standardMaxWidth: CGFloat
            let additionalBottomInset: CGFloat
            
            if itemContainer.node.wantsFullWidth {
                itemContainerConstrainedSize = CGSize(width: constrainedSize.width, height: itemConstrainedHeight)
                standardMaxWidth = 240.0
                standardMinWidth = standardMaxWidth
                
                if let (tipNode, tipHeight) = itemContainer.updateTip(presentationData: presentationData, presentation: presentation, width: standardMaxWidth, transition: itemContainerTransition) {
                    tip = TipLayout(tipNode: tipNode, tipHeight: tipHeight)
                    additionalBottomInset = tipHeight + 10.0
                } else {
                    additionalBottomInset = 0.0
                }
            } else {
                itemContainerConstrainedSize = CGSize(width: constrainedSize.width, height: itemConstrainedHeight)
                standardMinWidth = 220.0
                standardMaxWidth = 240.0
                additionalBottomInset = 0.0
            }
            
            let itemSize = itemContainer.update(
                presentationData: presentationData,
                constrainedSize: itemContainerConstrainedSize,
                standardMinWidth: standardMinWidth,
                standardMaxWidth: standardMaxWidth,
                additionalBottomInset: additionalBottomInset,
                transitionFraction: alphaTransitionFraction,
                transition: itemContainerTransition
            )
            if i == self.itemContainers.count - 1 {
                topItemSize = itemSize.size
            }
            
            if !itemContainer.node.wantsFullWidth {
                if let (tipNode, tipHeight) = itemContainer.updateTip(presentationData: presentationData, presentation: presentation, width: itemSize.size.width, transition: itemContainerTransition) {
                    tip = TipLayout(tipNode: tipNode, tipHeight: tipHeight)
                }
            }
            
            itemLayouts.append(ItemLayout(
                size: itemSize.size,
                apparentHeight: itemSize.apparentHeight,
                transitionFraction: transitionFraction,
                alphaTransitionFraction: alphaTransitionFraction,
                itemTransition: itemContainerTransition,
                animateAppearingContainer: animateAppearingContainer,
                tip: tip
            ))
        }
        
        let topItemApparentHeight: CGFloat
        let topItemWidth: CGFloat
        if itemLayouts.isEmpty {
            topItemApparentHeight = 0.0
            topItemWidth = 0.0
        } else if itemLayouts.count == 1 {
            topItemApparentHeight = itemLayouts[0].apparentHeight
            topItemWidth = itemLayouts[0].size.width
        } else {
            let lastItemLayout = itemLayouts[itemLayouts.count - 1]
            let previousItemLayout = itemLayouts[itemLayouts.count - 2]
            let transitionFraction = self.navigationContainer.transitionFraction
            
            topItemApparentHeight = lastItemLayout.apparentHeight * (1.0 - transitionFraction) + previousItemLayout.apparentHeight * transitionFraction
            topItemWidth = lastItemLayout.size.width * (1.0 - transitionFraction) + previousItemLayout.size.width * transitionFraction
        }
        
        let navigationContainerFrame: CGRect
        if topItemApparentHeight > 0.0 {
            navigationContainerFrame = CGRect(origin: CGPoint(), size: CGSize(width: topItemWidth, height: max(14 * 2.0, topItemApparentHeight)))
        } else {
            navigationContainerFrame = .zero
        }
        let previousNavigationContainerFrame = self.navigationContainer.frame
        transition.updateFrame(node: self.navigationContainer, frame: navigationContainerFrame, beginWithCurrentState: true)
        self.navigationContainer.update(presentationData: presentationData, presentation: presentation, size: navigationContainerFrame.size, transition: transition)
        
        let navigationContainerShadowFrame = navigationContainerFrame.insetBy(dx: -30.0, dy: -30.0)
        transition.updateFrame(node: self.navigationContainer.parentShadowNode, frame: navigationContainerShadowFrame, beginWithCurrentState: true)
        
        for i in 0 ..< self.itemContainers.count {
            let xOffset: CGFloat
            if itemLayouts[i].transitionFraction < 0.0 {
                xOffset = itemLayouts[i].transitionFraction * itemLayouts[i].size.width
            } else {
                if i != 0 {
                    xOffset = itemLayouts[i].transitionFraction * itemLayouts[i - 1].size.width
                } else {
                    xOffset = itemLayouts[i].transitionFraction * topItemWidth
                }
            }
            let itemFrame = CGRect(origin: CGPoint(x: xOffset, y: 0.0), size: CGSize(width: itemLayouts[i].size.width, height: navigationContainerFrame.height))
            
            itemLayouts[i].itemTransition.updateFrame(node: self.itemContainers[i], frame: itemFrame, beginWithCurrentState: true)
            if itemLayouts[i].animateAppearingContainer {
                transition.animatePositionAdditive(node: self.itemContainers[i], offset: CGPoint(x: itemFrame.width, y: 0.0))
            }
            
            self.itemContainers[i].updateDimNode(presentationData: presentationData, size: CGSize(width: itemLayouts[i].size.width, height: navigationContainerFrame.size.height), transitionFraction: itemLayouts[i].alphaTransitionFraction, transition: transition)
            
            if let tip = itemLayouts[i].tip {
                let tipTransition = transition
                var animateTipIn = false
                if tip.tipNode.supernode == nil {
                    self.insertSubnode(tip.tipNode.shadowNode, at: 0)
                    self.addSubnode(tip.tipNode)
                    animateTipIn = transition.isAnimated
                    let tipFrame = CGRect(origin: CGPoint(x: previousNavigationContainerFrame.minX, y: previousNavigationContainerFrame.maxY + tipSpacing), size: CGSize(width: itemLayouts[i].size.width, height: tip.tipHeight))
                    tip.tipNode.frame = tipFrame
                    tip.tipNode.setActualSize(size: tipFrame.size, transition: .immediate)
                    transition.updateFrame(node: tip.tipNode.shadowNode, frame: tipFrame.insetBy(dx: -30.0, dy: -30.0))
                }
                
                let tipAlpha: CGFloat = itemLayouts[i].alphaTransitionFraction
                
                let tipFrame = CGRect(origin: CGPoint(x: navigationContainerFrame.minX, y: navigationContainerFrame.maxY + tipSpacing), size: CGSize(width: itemLayouts[i].size.width, height: tip.tipHeight))
                tipTransition.updateFrame(node: tip.tipNode, frame: tipFrame, beginWithCurrentState: true)
                transition.updateFrame(node: tip.tipNode.shadowNode, frame: tipFrame.insetBy(dx: -30.0, dy: -30.0))
                
                tip.tipNode.setActualSize(size: tip.tipNode.bounds.size, transition: tipTransition)
                
                if animateTipIn {
                    tip.tipNode.alpha = tipAlpha
                    tip.tipNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                    
                    tip.tipNode.shadowNode.alpha = tipAlpha
                    tip.tipNode.shadowNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                } else {
                    tipTransition.updateAlpha(node: tip.tipNode, alpha: tipAlpha, beginWithCurrentState: true)
                    tipTransition.updateAlpha(node: tip.tipNode.shadowNode, alpha: tipAlpha, beginWithCurrentState: true)
                }
                
                if i == self.itemContainers.count - 1 {
                    topItemSize.height += tipSpacing + tip.tipHeight
                }
            }
        }
        
        for (itemContainer, isPopped) in self.dismissingItemContainers {
            var position = itemContainer.position
            if isPopped {
                position.x = itemContainer.bounds.width / 2.0 + topItemWidth
            } else {
                position.x = itemContainer.bounds.width / 2.0 - topItemWidth
            }
            transition.updatePosition(node: itemContainer, position: position, completion: { [weak itemContainer] _ in
                itemContainer?.removeFromSupernode()
            })
            if let tipNode = itemContainer.tipNode {
                let tipFrame = CGRect(origin: CGPoint(x: navigationContainerFrame.minX, y: navigationContainerFrame.maxY + tipSpacing), size: tipNode.frame.size)
                transition.updateFrame(node: tipNode, frame: tipFrame, beginWithCurrentState: true)
                transition.updateFrame(node: tipNode.shadowNode, frame: tipFrame.insetBy(dx: -30.0, dy: -30.0))
                
                transition.updateAlpha(node: tipNode, alpha: 0.0, completion: { [weak tipNode] _ in
                    tipNode?.removeFromSupernode()
                })
                let shadowNode = tipNode.shadowNode
                transition.updateAlpha(node: shadowNode, alpha: 0.0, completion: { [weak shadowNode] _ in
                    shadowNode?.removeFromSupernode()
                })
            }
        }
        self.dismissingItemContainers.removeAll()
        
        return CGSize(width: topItemWidth, height: topItemSize.height)
    }
    
    public func highlightGestureMoved(location: CGPoint) {
        if let topItemContainer = self.itemContainers.last {
            topItemContainer.highlightGestureMoved(location: self.view.convert(location, to: topItemContainer.view))
        }
    }
    
    public func highlightGestureFinished(performAction: Bool) {
        if let topItemContainer = self.itemContainers.last {
            topItemContainer.highlightGestureFinished(performAction: performAction)
        }
    }
    
    public func decreaseHighlightedIndex() {
        if let topItemContainer = self.itemContainers.last {
            topItemContainer.decreaseHighlightedIndex()
        }
    }
    
    public func increaseHighlightedIndex() {
        if let topItemContainer = self.itemContainers.last {
            topItemContainer.increaseHighlightedIndex()
        }
    }
    
    public func updatePanSelection(isEnabled: Bool) {
        if let selectionPanGesture = self.selectionPanGesture {
            selectionPanGesture.isEnabled = isEnabled
        }
    }
    
    public func animateIn() {
        for itemContainer in self.itemContainers {
            if let tipNode = itemContainer.tipNode {
                tipNode.animateIn()
            }
        }
    }
}
