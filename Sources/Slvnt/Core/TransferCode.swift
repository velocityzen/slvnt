import Foundation

/// The 4-digit transfer code shown on the player's screen during pairing.
public enum TransferCode {
    /// Validate against the player's `^\d{4}$` contract, trimming surrounding
    /// whitespace first. Lifts the nil/invalid case into the typed channel.
    public static func validate(_ raw: String) -> Result<String, SlvntError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let isFourDigits = trimmed.count == 4 && trimmed.allSatisfy { $0 >= "0" && $0 <= "9" }
        return isFourDigits ? .success(trimmed) : .failure(.invalidTransferCode(raw))
    }
}
