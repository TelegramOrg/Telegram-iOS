import Foundation
import UIKit

let walletAddressLength: Int = 48

func formatAddress(_ address: String) -> String {
    var address = address
    address.insert("\n", at: address.index(address.startIndex, offsetBy: address.count / 2))
    return address
}

func formatUsdValue(_ value: Int64, divide: Bool = true, rate: Double) -> String {
    let normalizedValue: Double = divide ? Double(value) / 1000000000 : Double(value)
    let formattedValue = String(format: "%0.2f", normalizedValue * rate)
    return "$\(formattedValue)"
}

func formatBalanceText(_ value: Int64, decimalSeparator: String, showPlus: Bool = false) -> String {
    var balanceText = "\(abs(value))"
    while balanceText.count < 10 {
        balanceText.insert("0", at: balanceText.startIndex)
    }
    balanceText.insert(contentsOf: decimalSeparator, at: balanceText.index(balanceText.endIndex, offsetBy: -9))
    while true {
        if balanceText.hasSuffix("0") {
            if balanceText.hasSuffix("\(decimalSeparator)0") {
                balanceText.removeLast()
                balanceText.removeLast()
                break
            } else {
                balanceText.removeLast()
            }
        } else {
            break
        }
    }
    if value < 0 {
        balanceText.insert("-", at: balanceText.startIndex)
    } else if showPlus {
        balanceText.insert("+", at: balanceText.startIndex)
    }
    
    if let dec = balanceText.range(of: decimalSeparator) {
        balanceText = String(balanceText[balanceText.startIndex ..< min(balanceText.endIndex, balanceText.index(dec.upperBound, offsetBy: 2))])
    }
    
    return balanceText
}

private let invalidAddressCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_=").inverted
func isValidAddress(_ address: String, exactLength: Bool = false) -> Bool {
    if address.count > walletAddressLength || address.rangeOfCharacter(from: invalidAddressCharacters) != nil {
        return false
    }
    if exactLength && address.count != walletAddressLength {
        return false
    }
    return true
}

private let amountDelimeterCharacters = CharacterSet(charactersIn: "0123456789-+").inverted
func amountAttributedString(_ string: String, integralFont: UIFont, fractionalFont: UIFont, color: UIColor) -> NSAttributedString {
    let result = NSMutableAttributedString()
    if let range = string.rangeOfCharacter(from: amountDelimeterCharacters) {
        let integralPart = String(string[..<range.lowerBound])
        let fractionalPart = String(string[range.lowerBound...])
        result.append(NSAttributedString(string: integralPart, font: integralFont, textColor: color))
        result.append(NSAttributedString(string: fractionalPart, font: fractionalFont, textColor: color))
    } else {
        result.append(NSAttributedString(string: string, font: integralFont, textColor: color))
    }
    return result
}
