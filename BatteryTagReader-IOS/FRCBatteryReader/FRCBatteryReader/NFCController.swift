import Foundation
import CoreNFC
import UIKit

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
}

// MARK: - Public API
extension NFCController {
    // READ
    func begin() {
        guard UIApplication.shared.applicationState == .active else { return }
        guard NFCNDEFReaderSession.readingAvailable else {
            self.presentHint("NFC not available on this device.")
            return
        }
        guard !nfcBusy else { return }

        // If a write session is up, end it before read
        writeSession?.invalidate(); writeSession = nil
        readSession?.invalidate(); readSession = nil

        let s = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: true)
        s.alertMessage = "Hold battery to phone"
        readSession = s
        nfcBusy = true
        s.begin()
    }

    // WRITE
    func write(_ p: BatteryPayload, onLogged: @escaping (String)->Void) {
        guard UIApplication.shared.applicationState == .active else { return }
        guard NFCTagReaderSession.readingAvailable else {
            self.presentHint("NFC not available on this device.")
            return
        }
        // Avoid overlapping sessions
        if nfcBusy { return }
        nfcBusy = true

        // End any running sessions first
        readSession?.invalidate(); readSession = nil
        writeSession?.invalidate(); writeSession = nil

        // Save state to complete after detection
        pendingPayload = p
        pendingOnLogged = onLogged

        // Give CoreNFC a brief moment to release resources before starting a new session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard let s = NFCTagReaderSession(pollingOption: [.iso14443], delegate: self, queue: .main) else {
                self.nfcBusy = false
                return
            }
            s.alertMessage = "Hold near the tag to write"
            self.writeSession = s
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
        // Mark busy while the sheet is up
        nfcBusy = true
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        readSession = nil
        nfcBusy = false
        // Many invalidations are user-cancel or timeout; no alert needed here
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
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
        nfcBusy = true
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        writeSession = nil
        pendingPayload = nil
        pendingOnLogged = nil
        nfcBusy = false
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { return }

        session.connect(to: tag) { connectError in
            if let connectError = connectError {
                session.invalidate(errorMessage: "Connection failed: \(connectError.localizedDescription)")
                return
            }

            // Convert to NDEF-capable tag
            let ndefTag: NFCNDEFTag?
            switch tag {
            case .miFare(let t):   ndefTag = t     // Type 2 (NTAG/Ultralight) shows up here
            case .iso7816(let t):  ndefTag = t
            case .iso15693(let t): ndefTag = t
            case .feliCa(let t):   ndefTag = t
            @unknown default:      ndefTag = nil
            }
            guard let ndefTag = ndefTag else {
                session.invalidate(errorMessage: "Tag does not support NDEF.")
                return
            }

            ndefTag.queryNDEFStatus { status, _, statusError in
                if let statusError = statusError {
                    session.invalidate(errorMessage: "Status error: \(statusError.localizedDescription)")
                    return
                }
                guard status == .readWrite else {
                    session.invalidate(errorMessage: "Tag is not writable.")
                    return
                }
                guard let payloadToWrite = self.pendingPayload else {
                    session.invalidate(errorMessage: "Nothing to write.")
                    return
                }

                // Build message (single Text record with JSON)
                let json = (try? String(data: JSONEncoder().encode(payloadToWrite), encoding: .utf8)) ?? "{}"
                guard let rec = NFCNDEFPayload.wellKnownTypeTextPayload(string: json, locale: Locale(identifier: "en")) else {
                    session.invalidate(errorMessage: "Failed to create NDEF record.")
                    return
                }
                let msg = NFCNDEFMessage(records: [rec])

                ndefTag.writeNDEF(msg) { writeError in
                    if let writeError = writeError {
                        session.invalidate(errorMessage: "Write failed: \(writeError.localizedDescription)")
                    } else {
                        session.alertMessage = "Write successful"
                        session.invalidate()
                        DispatchQueue.main.async {
                            self.payload = payloadToWrite
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

    private func presentHint(_ title: String, msg: String = "") {
        let ac = UIAlertController(title: title, message: msg.isEmpty ? nil : msg, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        UIApplication.shared.keyWindowTop?.present(ac, animated: true)
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
