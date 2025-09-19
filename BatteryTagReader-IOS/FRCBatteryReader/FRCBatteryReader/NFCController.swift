//
//  NFCController.swift
//  FRCBatteryReader
//

import Foundation
import CoreNFC
import UIKit
import OSLog

final class NFCController: NSObject, ObservableObject {
    @Published var payload: BatteryPayload? = nil

    // Single CoreNFC session (we use NDEF for both read and write)
    var readSession: NFCNDEFReaderSession?

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

            // Ensure pure read mode
            self.isWriting = false
            self.pendingPayload = nil
            self.pendingOnLogged = nil

            guard UIApplication.shared.applicationState == .active else { return }
            guard NFCNDEFReaderSession.readingAvailable else {
                self.presentHint("NFC not available on this device.")
                return
            }
            guard !self.nfcBusy else { return }

            // End any running session first
            self.readSession?.invalidate()
            self.readSession = nil

            let s = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: false)
            s.alertMessage = "Hold battery to phone"
            self.readSession = s
            self.nfcBusy = true
            s.begin()
        }
    }

    // WRITE (via NDEF Reader session — compatibility mode)
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

            // Mark write state
            self.nfcBusy = true
            self.isWriting = true
            self.pendingPayload = p
            self.pendingOnLogged = onLogged

            // End any running session first
            self.readSession?.invalidate()
            self.readSession = nil

            // Use NDEF reader session for write compatibility
            let s = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: false)
            s.alertMessage = "Hold near the tag to write"
            self.readSession = s
            s.begin()
        }
    }

    /// Re-present the write sheet if needed
    func restartWritePrompt() {
        guard let payload = pendingPayload, let onLogged = pendingOnLogged else { return }
        write(payload, onLogged: onLogged)
    }
}

// MARK: - NDEF delegate
extension NFCController: NFCNDEFReaderSessionDelegate {
    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        print("[NFC] NDEF reader active")
        logger.debug("NDEF reader active")
        nfcBusy = true
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        let ns = error as NSError
        print("[NFC] NDEF reader invalidated: \(ns.domain) \(ns.code) \(error.localizedDescription)")
        logger.debug("NDEF reader invalidated: \(ns.domain, privacy: .public) \(ns.code, privacy: .public)")
        // Clear session and state
        readSession = nil
        nfcBusy = false
        isWriting = false
        pendingPayload = nil
        pendingOnLogged = nil
    }

    // Passive message callback (some devices/OSes never call this; we also read via tag path below)
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        if isWriting {
            print("[NFC] didDetectNDEFs ignored (currently writing)")
            logger.debug("didDetectNDEFs ignored (writing)")
            return
        }

        print("[NFC] didDetectNDEFs count=\(messages.count)")
        logger.debug("didDetectNDEFs count=\(messages.count)")

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
            self.readSession = nil
            self.nfcBusy = false
            return
        }

        self.onReadRaw?(json)
        if let p = self.decodeBatteryPayload(fromJSON: json) {
            DispatchQueue.main.async { self.payload = p }
            session.invalidate()
            self.readSession = nil
            self.nfcBusy = false
        } else {
            print("[NFC] Text record present but JSON did not match schema")
            logger.debug("text record present but JSON did not match schema")
            session.invalidate(errorMessage: "Found text record but JSON didn’t match the app schema.")
            self.readSession = nil
            self.nfcBusy = false
        }
    }

    // Tag callback (used for BOTH write and read via NDEF session)
    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        print("[NFC] didDetect NDEF tags count=\(tags.count)")
        logger.debug("didDetect NDEF tags count=\(tags.count)")

        if tags.count > 1 {
            session.alertMessage = "More than one tag detected. Remove other tags and try again."
            session.restartPolling()
            return
        }
        guard let tag = tags.first else { return }

        session.connect(to: tag) { connectError in
            if let connectError = connectError {
                session.invalidate(errorMessage: "Connection failed: \(connectError.localizedDescription)")
                self.readSession = nil
                self.nfcBusy = false
                self.isWriting = false
                return
            }

            // WRITE MODE
            if self.isWriting {
                tag.queryNDEFStatus { status, capacity, statusError in
                    if let e = statusError {
                        session.invalidate(errorMessage: "Status error: \(e.localizedDescription)")
                        self.cleanupWriteState(); return
                    }
                    switch status {
                    case .notSupported:
                        session.invalidate(errorMessage: "Tag is not NDEF formatted or not supported.")
                        self.cleanupWriteState(); return
                    case .readOnly:
                        session.invalidate(errorMessage: "Tag is read-only.")
                        self.cleanupWriteState(); return
                    case .readWrite:
                        break
                    @unknown default:
                        session.invalidate(errorMessage: "Unknown NDEF status.")
                        self.cleanupWriteState(); return
                    }

                    guard let payloadToWrite = self.pendingPayload else {
                        session.invalidate(errorMessage: "Nothing to write.")
                        self.cleanupWriteState(); return
                    }

                    // Cap to 13 entries (Android parity)
                    let capped = self.cappedPayload(payloadToWrite, maxEntries: MAX_RECORDS)

                    // Build compact TEXT record that fits capacity
                    guard let (msg, json) = buildMessageFittingCapacity(capped, capacity: capacity) else {
                        session.invalidate(errorMessage: "Data too large for tag (capacity: \(capacity) bytes). Use NTAG215/216 or clear older history.")
                        self.cleanupWriteState(); return
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
                return
            }

            // READ MODE (reliable on all devices)
            tag.queryNDEFStatus { status, _, statusError in
                if let e = statusError {
                    session.invalidate(errorMessage: "Status error: \(e.localizedDescription)")
                    self.readSession = nil
                    self.nfcBusy = false
                    return
                }
                switch status {
                case .notSupported:
                    session.invalidate(errorMessage: "Tag is not NDEF formatted or not supported.")
                    self.readSession = nil
                    self.nfcBusy = false
                    return
                case .readOnly, .readWrite:
                    break
                @unknown default:
                    session.invalidate(errorMessage: "Unknown NDEF status.")
                    self.readSession = nil
                    self.nfcBusy = false
                    return
                }

                tag.readNDEF { message, readError in
                    if let readError = readError {
                        session.invalidate(errorMessage: "Read failed: \(readError.localizedDescription)")
                        self.readSession = nil
                        self.nfcBusy = false
                        return
                    }
                    guard let message = message else {
                        session.invalidate(errorMessage: "No NDEF message found on tag.")
                        self.readSession = nil
                        self.nfcBusy = false
                        return
                    }

                    var foundText: String? = nil
                    for rec in message.records {
                        if let s = NFCController.decodeText(from: rec) {
                            foundText = s
                            break
                        }
                    }

                    guard let json = foundText else {
                        session.invalidate(errorMessage: "No compatible text record found on tag.")
                        self.readSession = nil
                        self.nfcBusy = false
                        return
                    }

                    self.onReadRaw?(json)
                    if let p = self.decodeBatteryPayload(fromJSON: json) {
                        DispatchQueue.main.async { self.payload = p }
                        session.invalidate()
                        self.readSession = nil
                        self.nfcBusy = false
                    } else {
                        session.invalidate(errorMessage: "Found text record but JSON didn’t match the app schema.")
                        self.readSession = nil
                        self.nfcBusy = false
                    }
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
        // readSession is invalidated by the system after we call session.invalidate()
    }

    /// Decode a text string from an NDEF record. Supports Well-Known Text ("T") and MIME `text/plain`.
    static func decodeText(from record: NFCNDEFPayload) -> String? {
        switch record.typeNameFormat {
        case .nfcWellKnown:
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
            if let mime = String(data: record.type, encoding: .utf8), mime.lowercased() == "text/plain" {
                if let s = String(data: record.payload, encoding: .utf8) { return s }
                if let s = String(data: record.payload, encoding: .utf16) { return s }
            }
            return nil

        default:
            return nil
        }
    }

    /// Return a copy of the payload keeping only the most recent `maxEntries` usage items
    private func cappedPayload(_ p: BatteryPayload, maxEntries: Int = MAX_RECORDS) -> BatteryPayload {
        var copy = p
        if copy.u.count > maxEntries {
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

    /// Decode BatteryPayload from JSON, with a compatibility pass that coerces floating-point voltages to integers if needed.
    private func decodeBatteryPayload(fromJSON json: String) -> BatteryPayload? {
        let dec = JSONDecoder()
        if let data = json.data(using: .utf8),
           let p = try? dec.decode(BatteryPayload.self, from: data) {
            return p
        }
        // Compatibility path: if model expects Int for "v" but JSON has 12.1, coerce to Int and try again.
        if let coerced = NFCController.coerceVoltagesToInt(json),
           let data2 = coerced.data(using: .utf8),
           let p2 = try? dec.decode(BatteryPayload.self, from: data2) {
            return p2
        }
        return nil
    }

    /// If the JSON contains floating-point "v" fields inside the "u" array, round them to Int and return a rewritten JSON string.
    private static func coerceVoltagesToInt(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              var root = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }
        guard var arr = root["u"] as? [[String: Any]] else { return nil }
        var changed = false
        for i in 0 ..< arr.count {
            if let v = arr[i]["v"] as? Double {
                arr[i]["v"] = Int(v.rounded())
                changed = true
            }
        }
        guard changed else { return nil }
        root["u"] = arr
        guard let outData = try? JSONSerialization.data(withJSONObject: root, options: []),
              let out = String(data: outData, encoding: .utf8) else {
            return nil
        }
        return out
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

// MARK: - NDEF builders

/// Encode without spaces/newlines to save bytes.
func compactJSON<T: Encodable>(_ value: T) -> String? {
    let enc = JSONEncoder()
    guard let data = try? enc.encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

/// Build a Text (RTD-T) NDEF message that **forces UTF-8** and language code "en".
func makeTextRecordMessage(_ json: String) -> NFCNDEFMessage? {
    guard let textData = json.data(using: .utf8) else { return nil }
    let lang = "en"
    guard let langData = lang.data(using: .utf8) else { return nil }

    // Status byte: bit7 = 0 (UTF-8), bits 0..5 = language length
    let status: UInt8 = UInt8(langData.count & 0x3F)

    var payload = Data([status])
    payload.append(langData)
    payload.append(textData)

    let type = Data("T".utf8)
    let rec = NFCNDEFPayload(format: .nfcWellKnown, type: type, identifier: Data(), payload: payload)
    return NFCNDEFMessage(records: [rec])
}

/// Conservative estimate of NDEF message size in bytes.
func estimatedSize(of msg: NFCNDEFMessage, withTextPayload text: String) -> Int {
    let payloadBytes = text.utf8.count
    let textMeta = 3      // 1 status + 2 for "en"
    let header = 8        // SR header buffer
    return payloadBytes + textMeta + header
}

/// Try to fit by trimming oldest usage entries if needed.
func buildMessageFittingCapacity(_ full: BatteryPayload, capacity: Int) -> (NFCNDEFMessage, String)? {
    var work = full
    var attempts = max(1, work.u.count + 1)

    while attempts > 0 {
        attempts -= 1
        guard let json = compactJSON(work),
              let msg = makeTextRecordMessage(json) else { return nil }

        let size = estimatedSize(of: msg, withTextPayload: json)
        if size <= capacity {
            return (msg, json)
        }

        // Too large: drop exactly one oldest entry and retry
        if work.u.isEmpty { break }
        work.u.removeFirst(1)
    }

    return nil
}
