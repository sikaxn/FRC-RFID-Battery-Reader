//
//  NFCController.swift
//  FRCBatteryReader
//
//  Created by Nathan on 2025-09-13.
//

import Foundation
import CoreNFC
import UIKit

final class NFCController: NSObject, ObservableObject {
    @Published var payload: BatteryPayload? = nil

    // Separate sessions for read vs write
    private var readSession: NFCNDEFReaderSession?
    private var writeSession: NFCTagReaderSession?

    // Write state
    private var pendingPayload: BatteryPayload?
    private var pendingOnLogged: ((String) -> Void)?
}

// MARK: - Public API
extension NFCController {
    func begin() {
        guard NFCNDEFReaderSession.readingAvailable else { return }
        readSession = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: false)
        readSession?.alertMessage = "Hold battery to phone"
        readSession?.begin()
    }

    func write(_ p: BatteryPayload, onLogged: @escaping (String)->Void) {
        // Save state; start tag session (required for writing)
        guard NFCTagReaderSession.readingAvailable else { return }
        pendingPayload = p
        pendingOnLogged = onLogged

        writeSession = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693, .iso18092], delegate: self, queue: .main)
        writeSession?.alertMessage = "Hold near the tag to write"
        writeSession?.begin()
    }
}

// MARK: - NFCNDEFReaderSessionDelegate (READ)
extension NFCController: NFCNDEFReaderSessionDelegate {
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        // Read session ended or failed — typically user removed device or canceled
        // You can log error.localizedDescription if useful
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        guard let rec = messages.first?.records.first,
              let json = NFCController.textFrom(record: rec) else { return }

        DispatchQueue.main.async {
            if let p = try? JSONDecoder().decode(BatteryPayload.self, from: Data(json.utf8)) {
                self.payload = p
            }
        }
    }
}

// MARK: - NFCTagReaderSessionDelegate (WRITE)
extension NFCController: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // Session ready
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        // Write session ended or failed
        pendingPayload = nil
        pendingOnLogged = nil
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { return }

        // Connect to tag
        session.connect(to: tag) { connectError in
            if let connectError = connectError {
                session.invalidate(errorMessage: "Connection failed: \(connectError.localizedDescription)")
                return
            }

            // Convert to an NDEF-capable tag
            let ndefTag: NFCNDEFTag?
            switch tag {
            case .iso7816(let t):   ndefTag = t
            case .iso15693(let t):  ndefTag = t
            case .miFare(let t):    ndefTag = t
            case .feliCa(let t):    ndefTag = t
            @unknown default:       ndefTag = nil
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
                    // Clear state either way
                    self.pendingPayload = nil
                    self.pendingOnLogged = nil
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
}

// MARK: - Top-most VC helper
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
