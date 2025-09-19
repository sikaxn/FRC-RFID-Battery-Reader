import SwiftUI

struct ContentView: View {
    @StateObject private var nfc = NFCTextManager()
    @State private var textToWrite: String = "Hello, NFC!"

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Current Tag Text")) {
                    Text(nfc.lastReadText.isEmpty ? "— (none) —" : nfc.lastReadText)
                        .font(.body.monospaced())
                        .lineLimit(nil)
                }

                Section {
                    Button("Read Tag") {
                        nfc.beginRead()
                    }
                }

                Section(header: Text("Write New Text")) {
                    TextField("Enter text…", text: $textToWrite)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)

                    Button("Write Tag") {
                        nfc.beginWrite(text: textToWrite)
                    }
                }

                Section(header: Text("Status")) {
                    Text(nfc.status)
                        .font(.footnote)
                }
            }
            .navigationTitle("NDEF Text RW")
        }
    }
}

#Preview {
    ContentView()
}
