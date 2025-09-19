import Foundation
import CoreNFC
import UIKit
import OSLog

final class NFCController: NSObject, ObservableObject {
    @Published var payload: BatteryPayload? = nil

    // Keep strong references
    var readSession: NFCNDEFReaderSession?
    var writeSession: NFCTagReaderSession?

    // Pending write state
    private var pendingPayload: BatteryPayload?
    private var pendingOnLogged: ((String) -> Void)?
    // Raw read logging callback
    var onReadRaw: ((String) -> Void)?

    // Prevent overlapping sessions
    private var nfcBusy = false
    private var isWriting = false

    private let logger = Logger(subsystem: "FRCBatteryReader", category: "NFC")
}

// MARK: - Public API
extension NFCController {
    // READ
    func begin() {
        DispatchQueue.main.async {
            print("[NFC] begin() invoked")
            self.logger.debug("begin() invoked")
            // Ensure we are in pure read mode
            self.isWriting = false
            self.pendingPayload = nil
            self.pendingOnLogged = nil
            guard UIApplication.shared.applicationState == .active else { return }
            guard NFCNDEFReaderSession.readingAvailable else {
                self.presentHint("NFC not available on this device.")
                return
            }
            guard !self.nfcBusy else { return }

            // End any running sessions first
            self.writeSession?.invalidate(); self.writeSession = nil
            self.readSession?.invalidate(); self.readSession = nil

            let s = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: true)
            s.alertMessage = "Hold battery to phone"
            self.readSession = s
            self.nfcBusy = true
            s.begin()
        }
    }

    // WRITE
    func write(_ p: BatteryPayload, onLogged: @escaping (String)->Void) {
        DispatchQueue.main.async {
            print("[NFC] write() invoked (NDEF session)")
            self.logger.debug("write() invoked (NDEF)")
            guard UIApplication.shared.applicationState == .active else { return }
            guard NFCNDEFReaderSession.readingAvailable else {
                self.presentHint("NFC not available on this device.")
                return
            }
            if self.nfcBusy {
                print("[NFC] write() blocked: busy")
                self.logger.debug("write() blocked: busy")
                self.presentHint("NFC busy", msg: "Finish previous operation and try again.")
                return
            }

            // mark state
            self.nfcBusy = true
            self.isWriting = true
            self.pendingPayload = p
            self.pendingOnLogged = onLogged

            // End any running sessions first
            self.writeSession?.invalidate(); self.writeSession = nil
            self.readSession?.invalidate(); self.readSession = nil

            // Use NDEF reader session for write compatibility
            let s = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: false)
            s.alertMessage = "Hold near the tag to write"
            self.readSession = s
            s.begin()
        }
    }
    
    /// Use this if you want to explicitly re-present the system “Ready to scan” sheet.
    func restartWritePrompt() {
        guard let payload = pendingPayload, let onLogged = pendingOnLogged else { return }
        write(payload, onLogged: onLogged)
    }
}

// MARK: - READ delegate
extension NFCController: NFCNDEFReaderSessionDelegate {
    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        print("[NFC] NDEF reader active")
        logger.debug("NDEF reader active")
        // Mark busy while the sheet is up
        nfcBusy = true
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        let ns = error as NSError
        print("[NFC] NDEF reader invalidated: \(ns.domain) \(ns.code) \(error.localizedDescription)")
        logger.debug("NDEF reader invalidated: \(ns.domain, privacy: .public) \(ns.code, privacy: .public)")
        readSession = nil
        nfcBusy = false
        // Reset any pending write state so normal scanning works next time
        isWriting = false
        pendingPayload = nil
        pendingOnLogged = nil
        // Many invalidations are user-cancel or timeout; no alert needed here
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // If we're in write-mode, ignore passive NDEF message callbacks
        if isWriting { return }

        print("[NFC] didDetectNDEFs count=\(messages.count)")
        logger.debug("didDetectNDEFs count=\(messages.count)")

        // Try to find a text payload across all records in all messages
        var foundText: String? = nil
        outer: for msg in messages {
            for rec in msg.records {
                if let s = NFCController.decodeText(from: rec) {
                    foundText = s
                    break outer
                }
            }
        }

        guard let json = foundText else {
            print("[NFC] No compatible text record (T or text/plain) found")
            logger.debug("no compatible text record")
            session.invalidate(errorMessage: "No compatible text record found on tag.")
            nfcBusy = false
            return
        }

        // Log raw read prior to decode
        self.onReadRaw?(json)
        if let data = json.data(using: .utf8), let p = try? JSONDecoder().decode(BatteryPayload.self, from: data) {
            DispatchQueue.main.async { self.payload = p }
            // Close the sheet after one successful parse
            session.invalidate()
            nfcBusy = false
        } else {
            print("[NFC] Text record present but JSON decode failed")
            logger.debug("text record present but JSON decode failed")
            session.invalidate(errorMessage: "Found text record but JSON was invalid.")
            nfcBusy = false
        }
    }

    // Handle write using NDEF session (compatibility mode). Called when tags are detected.
    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        print("[NFC] didDetect NDEF tags count=\(tags.count)")
        logger.debug("didDetect NDEF tags count=\(tags.count)")

        guard isWriting else {
            // not writing: if multiple tags, prompt isolate and restart
            if tags.count > 1 {
                session.alertMessage = "More than one tag detected. Remove other tags and try again."
                session.restartPolling()
            }
            return
        }

        if tags.count > 1 {
            session.alertMessage = "More than one tag detected. Remove other tags and try again."
            session.restartPolling()
            return
        }
        guard let tag = tags.first else { return }

        session.connect(to: tag) { connectError in
            if let connectError = connectError {
                session.invalidate(errorMessage: "Connection failed: \(connectError.localizedDescription)")
                self.cleanupWriteState()
                return
            }

            tag.queryNDEFStatus { status, capacity, statusError in
                if let e = statusError {
                    session.invalidate(errorMessage: "Status error: \(e.localizedDescription)")
                    self.cleanupWriteState()
                    return
                }
                switch status {
                case .notSupported:
                    session.invalidate(errorMessage: "Tag is not NDEF formatted or not supported.")
                    self.cleanupWriteState()
                    return
                case .readOnly:
                    session.invalidate(errorMessage: "Tag is read-only.")
                    self.cleanupWriteState()
                    return
                case .readWrite:
                    break
                @unknown default:
                    session.invalidate(errorMessage: "Unknown NDEF status.")
                    self.cleanupWriteState()
                    return
                }

                guard let payloadToWrite = self.pendingPayload else {
                    session.invalidate(errorMessage: "Nothing to write.")
                    self.cleanupWriteState()
                    return
                }

                // Cap usage history to 13 entries (Android parity)
                let capped = self.cappedPayload(payloadToWrite, maxEntries: 13)

                // Build compact TEXT record that fits capacity
                guard let (msg, json) = buildMessageFittingCapacity(capped, capacity: capacity) else {
                    session.invalidate(errorMessage: "Data too large for tag (capacity: \(capacity) bytes). Use NTAG215/216 or clear older history.")
                    self.cleanupWriteState()
                    return
                }

                print("[NFC] writing NDEF Text record (bytes est=\(estimatedSize(of: msg, withTextPayload: json)))")
                self.logger.debug("writing NDEF Text record")

                tag.writeNDEF(msg) { writeError in
                    if let writeError = writeError {
                        session.invalidate(errorMessage: "Write failed: \(writeError.localizedDescription)")
                    } else {
                        session.alertMessage = "Write successful"
                        session.invalidate()
                        print("[NFC] write successful")
                        self.logger.debug("write successful")
                        DispatchQueue.main.async {
                            self.payload = capped
                            self.pendingOnLogged?(json)
                        }
                    }
                    self.cleanupWriteState()
                }
            }
        }
    }
}

// MARK: - WRITE delegate
// NOTE: Tag session delegate remains for future use; write now uses NFCNDEFReaderSession.
extension NFCController: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        print("[NFC] Tag session active")
        logger.debug("Tag session active")
        nfcBusy = true
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        let ns = error as NSError
        print("[NFC] Tag session invalidated: \(ns.domain) \(ns.code) \(error.localizedDescription)")
        logger.debug("Tag session invalidated: \(ns.domain, privacy: .public) \(ns.code, privacy: .public)")
        writeSession = nil
        pendingPayload = nil
        pendingOnLogged = nil
        nfcBusy = false
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        print("[NFC] didDetect tags count=\(tags.count)")
        logger.debug("didDetect tags count=\(tags.count)")
        if tags.count > 1 {
            session.alertMessage = "More than one tag detected. Remove other tags and try again."
            session.restartPolling()
            return
        }
        guard let tag = tags.first else { return }

        session.connect(to: tag) { connectError in
            print("[NFC] connected to tag")
            self.logger.debug("connected to tag")
            if let connectError = connectError {
                session.invalidate(errorMessage: "Connection failed: \(connectError.localizedDescription)")
                return
            }

            // Convert to NDEF-capable tag
            let ndefTag: NFCNDEFTag?
            switch tag {
            case .miFare(let t):
                // Only Ultralight (NTAG/Type 2) and DESFire (Type 4) are writable on iOS.
                switch t.mifareFamily {
                case .ultralight, .desfire:
                    ndefTag = t
                default:
                    session.invalidate(errorMessage: "Unsupported MiFare family on iOS (e.g., Classic/Plus). Use NTAG (Type 2) or DESFire (Type 4).")
                    return
                }
            case .iso7816(let t):  ndefTag = t
            case .iso15693(let t): ndefTag = t
            case .feliCa(let t):   ndefTag = t
            @unknown default:      ndefTag = nil
            }
            guard let ndefTag = ndefTag else {
                session.invalidate(errorMessage: "Tag does not support NDEF.")
                return
            }

            ndefTag.queryNDEFStatus { status, capacity, statusError in
                if let statusError = statusError {
                    session.invalidate(errorMessage: "Status error: \(statusError.localizedDescription)")
                    return
                }
                switch status {
                case .notSupported:
                    session.invalidate(errorMessage: "Tag is not NDEF formatted or not supported.")
                    return
                case .readOnly:
                    session.invalidate(errorMessage: "Tag is read-only.")
                    return
                case .readWrite:
                    break
                @unknown default:
                    session.invalidate(errorMessage: "Unknown NDEF status.")
                    return
                }
                guard let payloadToWrite = self.pendingPayload else {
                    session.invalidate(errorMessage: "Nothing to write.")
                    return
                }

                // Cap usage history to 13 entries (Android parity)
                let capped = self.cappedPayload(payloadToWrite, maxEntries: 13)

                // Build compact message that fits capacity
                guard let (msg, json) = buildMessageFittingCapacity(capped, capacity: capacity) else {
                    session.invalidate(errorMessage: "Data too large for tag (capacity: \(capacity) bytes). Use NTAG215/216 or clear older history.")
                    return
                }
                print("[NFC] writing NDEF Text record (bytes est=\(estimatedSize(of: msg, withTextPayload: json)))")
                self.logger.debug("writing NDEF Text record")

                ndefTag.writeNDEF(msg) { writeError in
                    if let writeError = writeError {
                        session.invalidate(errorMessage: "Write failed: \(writeError.localizedDescription)")
                    } else {
                        session.alertMessage = "Write successful"
                        session.invalidate()
                        print("[NFC] write successful")
                        self.logger.debug("write successful")
                        DispatchQueue.main.async {
                            self.payload = capped
                            self.pendingOnLogged?(json)
                        }
                    }
                    // Clear write state
                    self.pendingPayload = nil
                    self.pendingOnLogged = nil
                    self.nfcBusy = false
                }
            }
        }
    }
}

// MARK: - Helpers
extension NFCController {
    private func cleanupWriteState() {
        self.pendingPayload = nil
        self.pendingOnLogged = nil
        self.isWriting = false
        self.nfcBusy = false
        self.writeSession = nil
        // readSession is invalidated by the system after we call session.invalidate()
    }
    /// Decode a text string from an NDEF record. Supports Well-Known Text ("T") and MIME `text/plain`.
    static func decodeText(from record: NFCNDEFPayload) -> String? {
        switch record.typeNameFormat {
        case .nfcWellKnown:
            // Well-known type; expect "T" (RTD_TEXT)
            guard let typeString = String(data: record.type, encoding: .utf8), typeString == "T" else { return nil }
            let payload = record.payload
            guard payload.count > 0 else { return nil }
            let status = payload[payload.startIndex]
            let isUTF16 = (status & 0x80) != 0
            let langLen = Int(status & 0x3F)
            guard payload.count >= 1 + langLen else { return nil }
            let textData = payload.dropFirst(1 + langLen)
            return String(data: textData, encoding: isUTF16 ? .utf16 : .utf8)

        case .media:
            // MIME type like "text/plain"
            if let mime = String(data: record.type, encoding: .utf8), mime.lowercased() == "text/plain" {
                // Try UTF-8 first, then UTF-16
                if let s = String(data: record.payload, encoding: .utf8) { return s }
                if let s = String(data: record.payload, encoding: .utf16) { return s }
            }
            return nil

        default:
            return nil
        }
    }

    /// Return a copy of the payload keeping only the most recent `maxEntries` usage items
    private func cappedPayload(_ p: BatteryPayload, maxEntries: Int = 13) -> BatteryPayload {
        var copy = p
        if copy.u.count > maxEntries {
            // Keep the newest N entries (highest indices / most recent timestamps)
            copy.u = Array(copy.u.suffix(maxEntries))
        }
        return copy
    }

    private func presentHint(_ title: String, msg: String = "") {
        DispatchQueue.main.async {
            let ac = UIAlertController(title: title, message: msg.isEmpty ? nil : msg, preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            if let top = UIApplication.shared.keyWindowTop {
                top.present(ac, animated: true)
            } else if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
                      let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                root.topMost.present(ac, animated: true)
            }
        }
    }

    // MARK: - Debug helper
    func debugStartWriteSessionOnly() {
        DispatchQueue.main.async {
            print("[NFC] debugStartWriteSessionOnly() invoked")
            self.logger.debug("debugStartWriteSessionOnly() invoked")
            guard let s = NFCTagReaderSession(pollingOption: [.iso14443], delegate: self, queue: .main) else {
                self.presentHint("NFC Tag session not permitted", msg: "Check TAG entitlement and Code Signing Entitlements path.")
                return
            }
            s.alertMessage = "Write-session test: hold tag"
            self.writeSession = s
            s.begin()
        }
    }
}

extension UIApplication {
    var keyWindowTop: UIViewController? {
        let scenes = self.connectedScenes.compactMap { $0 as? UIWindowScene }
        for s in scenes {
            for w in s.windows where w.isKeyWindow {
                return w.rootViewController?.topMost
            }
        }
        return nil
    }
}
extension UIViewController {
    var topMost: UIViewController { presentedViewController?.topMost ?? self }
}


/// Encode without spaces/newlines to save bytes.
func compactJSON<T: Encodable>(_ value: T) -> String? {
    let enc = JSONEncoder()
    // default is already compact; ensure no prettyPrinted anywhere
    guard let data = try? enc.encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

/// Build a Text-record NDEF message from JSON string.
func makeTextRecordMessage(_ json: String) -> NFCNDEFMessage? {
    // Text record payload = 1 status byte + lang code bytes + text bytes
    guard let rec = NFCNDEFPayload.wellKnownTypeTextPayload(
        string: json,
        locale: Locale(identifier: "en")
    ) else { return nil }
    return NFCNDEFMessage(records: [rec])
}

/// Conservative estimate of NDEF message size in bytes.
/// (Payload + small header overhead buffer.)
func estimatedSize(of msg: NFCNDEFMessage, withTextPayload text: String) -> Int {
    // The text payload itself
    let payloadBytes = text.utf8.count
    // Status + "en"  (status=1 byte, "en"=2 bytes)
    let textMeta = 3
    // Record header (TNF + SR + ID flags, type len, payload len, type = "T")
    // SR makes header ~4 bytes; add a small buffer for safety.
    let header = 8
    return payloadBytes + textMeta + header
}

/// Try to fit by trimming oldest usage entries if needed.
func buildMessageFittingCapacity(_ full: BatteryPayload, capacity: Int) -> (NFCNDEFMessage, String)? {
    // Start from the full payload; drop oldest usages until it fits.
    var work = full
    // Defensive bound to avoid long loops
    var attempts = max(1, work.u.count + 1)

    while attempts > 0 {
        attempts -= 1
        guard let json = compactJSON(work),
              let msg = makeTextRecordMessage(json) else { return nil }

        let size = estimatedSize(of: msg, withTextPayload: json)
        if size <= capacity {
            return (msg, json)
        }

        // Too large: drop the oldest 5 entries (or 1 if fewer than 5 remain)
        let dropCount = min( max(1, work.u.count / 6), max(1, work.u.count) )
        if work.u.isEmpty { break }
        work.u.removeFirst(min(dropCount, work.u.count))
    }

    return nil
}
