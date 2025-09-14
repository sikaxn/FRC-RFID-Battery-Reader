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

    private let logger = Logger(subsystem: "FRCBatteryReader", category: "NFC")
}

// MARK: - Public API
extension NFCController {
    // READ
    func begin() {
        DispatchQueue.main.async {
            print("[NFC] begin() invoked")
            self.logger.debug("begin() invoked")
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
            print("[NFC] write() invoked")
            self.logger.debug("write() invoked")
            guard UIApplication.shared.applicationState == .active else { return }
            guard NFCTagReaderSession.readingAvailable else {
                self.presentHint("NFC not available on this device.")
                return
            }
            if self.nfcBusy {
                print("[NFC] write() blocked: busy")
                self.logger.debug("write() blocked: busy")
                self.presentHint("NFC busy", msg: "Finish previous operation and try again.")
                return
            }
            self.nfcBusy = true

            // End any running sessions first
            self.readSession?.invalidate(); self.readSession = nil
            self.writeSession?.invalidate(); self.writeSession = nil

            // Save state to complete after detection
            self.pendingPayload = p
            self.pendingOnLogged = onLogged

            // Start immediately on main (no extra gating); small delay is optional but safer
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                guard let s = NFCTagReaderSession(pollingOption: [.iso14443], delegate: self, queue: .main) else {
                    self.nfcBusy = false
                    self.presentHint("Failed to create NFC write session",
                                      msg: "Check TAG entitlement and rebuild to a real iPhone with NFC enabled.")
                    return
                }
                s.alertMessage = "Hold near the tag to write"
                self.writeSession = s
                print("[NFC] write() starting Tag session…")
                self.logger.debug("write() starting Tag session…")
                s.begin()
            }
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
        // Many invalidations are user-cancel or timeout; no alert needed here
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        print("[NFC] didDetectNDEFs count=\(messages.count)")
        logger.debug("didDetectNDEFs count=\(messages.count)")
        guard let rec = messages.first?.records.first,
              let json = NFCController.textFrom(record: rec) else { return }
        // Log raw read prior to decode
        self.onReadRaw?(json)
        DispatchQueue.main.async {
            if let p = try? JSONDecoder().decode(BatteryPayload.self, from: Data(json.utf8)) {
                self.payload = p
            }
        }
        // Close the sheet after one successful parse
        session.invalidate()
        nfcBusy = false
    }
}

// MARK: - WRITE delegate
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
    static func textFrom(record: NFCNDEFPayload) -> String? {
        guard record.typeNameFormat == .nfcWellKnown,
              let typeString = String(data: record.type, encoding: .utf8),
              typeString == "T" else { return nil }
        let payload = record.payload
        guard payload.count > 0 else { return nil }
        let status = payload[0]
        let langLen = Int(status & 0x3F)
        guard payload.count >= 1 + langLen else { return nil }
        let textData = payload.dropFirst(1 + langLen)
        return String(data: textData, encoding: .utf8)
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
