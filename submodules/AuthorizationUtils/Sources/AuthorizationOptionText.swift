import Foundation
import UIKit
import TelegramCore
import Display
import TelegramPresentationData
import TextFormat
import Markdown

public func authorizationCurrentOptionText(_ type: SentAuthorizationCodeType, phoneNumber: String, email: String?, strings: PresentationStrings, primaryColor: UIColor, accentColor: UIColor) -> NSAttributedString {
    let fontSize: CGFloat = 17.0
    let body = MarkdownAttributeSet(font: Font.regular(fontSize), textColor: primaryColor)
    let bold = MarkdownAttributeSet(font: Font.semibold(fontSize), textColor: primaryColor)
    let attributes = MarkdownAttributes(body: body, bold: bold, link: body, linkAttribute: { _ in nil })
    
    switch type {
    case .sms:
        return parseMarkdownIntoAttributedString(strings.Login_EnterCodeSMSText(phoneNumber).string, attributes: attributes, textAlignment: .center)
    case .otherSession:
        return parseMarkdownIntoAttributedString(strings.Login_EnterCodeTelegramText(phoneNumber).string, attributes: attributes, textAlignment: .center)
    case .missedCall:
        let body = MarkdownAttributeSet(font: Font.regular(fontSize), textColor: primaryColor)
        let bold = MarkdownAttributeSet(font: Font.semibold(fontSize), textColor: primaryColor)
        return parseMarkdownIntoAttributedString(strings.Login_ShortCallTitle, attributes: MarkdownAttributes(body: body, bold: bold, link: body, linkAttribute: { _ in nil }), textAlignment: .center)
    case .call:
        return parseMarkdownIntoAttributedString(strings.Login_CodeSentCallText(phoneNumber).string, attributes: attributes, textAlignment: .center)
    case .flashCall:
        return parseMarkdownIntoAttributedString(strings.Login_CodeSentCallText(phoneNumber).string, attributes: attributes, textAlignment: .center)
    case .emailSetupRequired:
        return NSAttributedString(string: "", font: Font.regular(fontSize), textColor: primaryColor, paragraphAlignment: .center)
    case let .email(emailPattern, _, _, _, _, _):
        let mutableString = NSAttributedString(string: strings.Login_EnterCodeEmailText(email ?? emailPattern).string, font: Font.regular(fontSize), textColor: primaryColor, paragraphAlignment: .center).mutableCopy() as! NSMutableAttributedString
        if let regex = try? NSRegularExpression(pattern: "\\*", options: []) {
            let matches = regex.matches(in: mutableString.string, options: [], range: NSMakeRange(0, mutableString.length))
            if let first = matches.first {
                mutableString.addAttribute(NSAttributedString.Key(rawValue: TelegramTextAttributes.Spoiler), value: true, range: NSRange(location: first.range.location, length: matches.count))
            }
        }

        return mutableString
    case .fragment:
        return parseMarkdownIntoAttributedString(strings.Login_EnterCodeFragmentText(phoneNumber).string, attributes: attributes, textAlignment: .center)
    case .firebase:
        return parseMarkdownIntoAttributedString(strings.Login_EnterCodeSMSText(phoneNumber).string, attributes: attributes, textAlignment: .center)
    case let .word(startsWith):
        if let startsWith {
            return parseMarkdownIntoAttributedString(strings.Login_EnterWordBeginningText(startsWith, phoneNumber).string, attributes: attributes, textAlignment: .center)
        } else {
            return parseMarkdownIntoAttributedString(strings.Login_EnterWordText(phoneNumber).string, attributes: attributes, textAlignment: .center)
        }
    case let .phrase(startsWith):
        if let startsWith {
            return parseMarkdownIntoAttributedString(strings.Login_EnterPhraseBeginningText(startsWith, phoneNumber).string, attributes: attributes, textAlignment: .center)
        } else {
            return parseMarkdownIntoAttributedString(strings.Login_EnterPhraseText(phoneNumber).string, attributes: attributes, textAlignment: .center)
        }
    }
}

public func authorizationNextOptionText(currentType: SentAuthorizationCodeType, nextType: AuthorizationCodeNextType?, previousCodeType: SentAuthorizationCodeType? = nil, timeout: Int32?, strings: PresentationStrings, primaryColor: UIColor, accentColor: UIColor) -> (NSAttributedString, Bool) {
    let font = Font.regular(16.0)
    
    if let previousCodeType {
        switch previousCodeType {
        case .word:
            return (NSAttributedString(string: strings.Login_ReturnToWord, font: font, textColor: accentColor, paragraphAlignment: .center), true)
        case .phrase:
            return (NSAttributedString(string: strings.Login_ReturnToPhrase, font: font, textColor: accentColor, paragraphAlignment: .center), true)
        default:
            return (NSAttributedString(string: strings.Login_ReturnToCode, font: font, textColor: accentColor, paragraphAlignment: .center), true)
        }
    }
    
    if let nextType = nextType, let timeout = timeout, timeout > 0 {
        let minutes = timeout / 60
        let seconds = timeout % 60
        switch nextType {
        case .sms:
            if timeout <= 0 {
                return (NSAttributedString(string: strings.Login_CodeSentSms, font: font, textColor: primaryColor, paragraphAlignment: .center), false)
            } else {
                let timeString = NSString(format: "%d:%.02d", Int(minutes), Int(seconds))
                return (NSAttributedString(string: strings.Login_WillSendSms(timeString as String).string, font: font, textColor: primaryColor, paragraphAlignment: .center), false)
            }
        case .call:
            if timeout <= 0 {
                return (NSAttributedString(string: strings.Login_CodeSentCall, font: font, textColor: primaryColor, paragraphAlignment: .center), false)
            } else {
                return (NSAttributedString(string: String(format: strings.ChangePhoneNumberCode_CallTimer(String(format: "%d:%.2d", minutes, seconds)).string, minutes, seconds), font: font, textColor: primaryColor, paragraphAlignment: .center), false)
            }
        case .flashCall, .missedCall:
            if timeout <= 0 {
                return (NSAttributedString(string: strings.ChangePhoneNumberCode_Called, font: font, textColor: primaryColor, paragraphAlignment: .center), false)
            } else {
                return (NSAttributedString(string: String(format: strings.ChangePhoneNumberCode_CallTimer(String(format: "%d:%.2d", minutes, seconds)).string, minutes, seconds), font: font, textColor: primaryColor, paragraphAlignment: .center), false)
            }
        case .fragment:
            if timeout <= 0 {
                return (NSAttributedString(string: strings.Login_CodeSentSms, font: font, textColor: primaryColor, paragraphAlignment: .center), false)
            } else {
                let timeString = NSString(format: "%d:%.02d", Int(minutes), Int(seconds))
                return (NSAttributedString(string: strings.Login_WillSendSms(timeString as String).string, font: font, textColor: primaryColor, paragraphAlignment: .center), false)
            }
        }
    } else {
        switch currentType {
        case .otherSession:
            switch nextType {
            case .sms:
                return (NSAttributedString(string: strings.Login_SendCodeViaSms, font: font, textColor: accentColor, paragraphAlignment: .center), true)
            case .call:
                return (NSAttributedString(string: strings.Login_SendCodeViaCall, font: font, textColor: accentColor, paragraphAlignment: .center), true)
            case .flashCall, .missedCall:
                return (NSAttributedString(string: strings.Login_SendCodeViaFlashCall, font: font, textColor: accentColor, paragraphAlignment: .center), true)
            case .fragment:
                return (NSAttributedString(string: strings.Login_GetCodeViaFragment, font: font, textColor: accentColor, paragraphAlignment: .center), true)
            case .none:
                return (NSAttributedString(string: strings.Login_HaveNotReceivedCodeInternal, font: font, textColor: accentColor, paragraphAlignment: .center), true)
            }
        default:
            switch nextType {
            case .sms:
                return (NSAttributedString(string: strings.Login_SendCodeViaSms, font: font, textColor: accentColor, paragraphAlignment: .center), true)
            case .call:
                return (NSAttributedString(string: strings.Login_SendCodeViaCall, font: font, textColor: accentColor, paragraphAlignment: .center), true)
            case .flashCall, .missedCall:
                return (NSAttributedString(string: strings.Login_SendCodeViaFlashCall, font: font, textColor: accentColor, paragraphAlignment: .center), true)
            case .fragment:
                return (NSAttributedString(string: strings.Login_GetCodeViaFragment, font: font, textColor: accentColor, paragraphAlignment: .center), true)
            case .none:
                return (NSAttributedString(string: strings.Login_HaveNotReceivedCodeInternal, font: font, textColor: accentColor, paragraphAlignment: .center), true)
            }
        }
    }
}
