import Foundation
import CoreNFC

/// Reads and (on iOS 13+) writes a single NDEF Text record.
final class NFCTextManager: NSObject, ObservableObject {
    @Published var lastReadText: String = ""
    @Published var status: String = "Idle"

    private var session: NFCNDEFReaderSession?
    private var pendingWriteText: String?
    private var intent: Intent = .read

    private enum Intent { case read, write, erase }

    // MARK: - Public API

    func beginRead() {
        intent = .read
        pendingWriteText = nil
        startSession(alert: "Hold your iPhone near the NFC tag to READ.")
    }

    func beginWrite(text: String) {
        intent = .write
        pendingWriteText = text
        startSession(alert: "Hold your iPhone near the NFC tag to WRITE.")
    }

    func beginErase() {
        intent = .erase
        pendingWriteText = nil
        startSession(alert: "Hold your iPhone near the NFC tag to ERASE.")
    }

    // MARK: - Session

    private func startSession(alert: String) {
        guard NFCNDEFReaderSession.readingAvailable else {
            self.status = "NFC not available on this device."
            return
        }

        // On iOS 11–12, NDEF sessions can READ only.
        if (intent == .write || intent == .erase) && !isAtLeastIOS13 {
            self.status = "Writing requires iOS 13 or later."
            return
        }

        session?.invalidate()
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session?.alertMessage = alert
        session?.begin()
        self.status = "Scanning…"
    }

    private func invalidate(_ message: String) {
        session?.invalidate()
        DispatchQueue.main.async { self.status = message }
    }

    // MARK: - Helpers

    private var isAtLeastIOS13: Bool {
        if #available(iOS 13.0, *) { return true } else { return false }
    }

    private func makeTextPayload(_ text: String) -> NFCNDEFPayload? {
        // Force NDEF RTD-Text (TNF=Well Known, type "T") with UTF-8 and lang code "en"
        let lang = "en"
        let langBytes = Array(lang.utf8)
        guard langBytes.count <= 63 else { return nil } // status byte lower 6 bits store lang length
        let status: UInt8 = UInt8(langBytes.count) // bit7=0 => UTF-8
        let textBytes = Array(text.utf8)

        var payload = Data([status])
        payload.append(contentsOf: langBytes)
        payload.append(contentsOf: textBytes)

        let type = Data([0x54]) // ASCII 'T'
        return NFCNDEFPayload(format: .nfcWellKnown, type: type, identifier: Data(), payload: payload)
    }

    private func firstText(from message: NFCNDEFMessage) -> String? {
        for record in message.records {
            let payload = record.wellKnownTypeTextPayload()
            if let text = payload.0 {   // payload.0 is String?
                return text
            }
        }
        return nil
    }
}

// MARK: - NFCNDEFReaderSessionDelegate (common)

extension NFCTextManager: NFCNDEFReaderSessionDelegate {
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async {
            self.status = "Session ended: \(error.localizedDescription)"
        }
        self.session = nil
    }

    // iOS 11–12: message-based detection (READ ONLY)
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Only reading is possible pre-iOS 13
        guard intent == .read else {
            session.alertMessage = "Writing requires iOS 13+."
            invalidate("Writing requires iOS 13+.")
            return
        }

        let text = messages.compactMap { firstText(from: $0) }.first ?? ""
        DispatchQueue.main.async {
            self.lastReadText = text
            self.status = "Read OK."
        }
        session.alertMessage = "Read complete."
        // Keep session open for more scans if desired
    }

    // iOS 13+: tag-based detection (READ/WRITE/ERASE)
    @available(iOS 13.0, *)
    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        if tags.count > 1 {
            session.alertMessage = "More than one tag detected. Present only one."
            // Only available iOS 13+
            session.restartPolling()
            return
        }

        let tag = tags[0]
        session.connect(to: tag) { connectError in
            if let connectError = connectError {
                session.alertMessage = "Failed to connect: \(connectError.localizedDescription)"
                self.invalidate("Connect error.")
                return
            }

            tag.queryNDEFStatus { (status, capacity, err) in
                if let err = err {
                    session.alertMessage = "Query error: \(err.localizedDescription)"
                    self.invalidate("Query error.")
                    return
                }

                switch self.intent {
                case .read:
                    guard status != .notSupported else {
                        session.alertMessage = "Tag not NDEF formatted."
                        self.invalidate("Not NDEF.")
                        return
                    }
                    tag.readNDEF { message, readErr in
                        if let readErr = readErr {
                            session.alertMessage = "Read failed: \(readErr.localizedDescription)"
                            self.invalidate("Read failed.")
                            return
                        }
                        let text = message.flatMap { self.firstText(from: $0) } ?? ""
                        DispatchQueue.main.async {
                            self.lastReadText = text
                            self.status = "Read OK."
                        }
                        session.alertMessage = "Read complete."
                    }

                case .write, .erase:
                    guard status != .notSupported else {
                        session.alertMessage = "Tag not NDEF formatted."
                        self.invalidate("Not NDEF.")
                        return
                    }
                    guard status == .readWrite else {
                        session.alertMessage = "Tag is read-only."
                        self.invalidate("Read-only tag.")
                        return
                    }

                    let payload: NFCNDEFPayload?
                    if self.intent == .erase {
                        payload = nil
                    } else if let text = self.pendingWriteText,
                              let p = self.makeTextPayload(text) {
                        payload = p
                    } else {
                        session.alertMessage = "No text to write."
                        self.invalidate("Nothing to write.")
                        return
                    }

                    let messageToWrite = NFCNDEFMessage(records: payload.map { [$0] } ?? [])
                    if messageToWrite.length > capacity {
                        session.alertMessage = "Message too large for tag."
                        self.invalidate("Too large.")
                        return
                    }

                    tag.writeNDEF(messageToWrite) { writeErr in
                        if let writeErr = writeErr {
                            session.alertMessage = "Write failed: \(writeErr.localizedDescription)"
                            self.invalidate("Write failed.")
                            return
                        }
                        session.alertMessage = (self.intent == .erase) ? "Erase complete." : "Write complete."
                        DispatchQueue.main.async {
                            self.status = (self.intent == .erase) ? "Erased." : "Write OK."
                            self.lastReadText = (self.intent == .erase) ? "" : (self.pendingWriteText ?? "")
                        }
                    }
                }
            }
        }
    }
}
