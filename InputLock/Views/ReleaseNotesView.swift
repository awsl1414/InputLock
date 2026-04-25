import SwiftUI

struct ReleaseNotesView: View {
    let notes: String
    let version: String
    @State private var attributedString: NSAttributedString?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("InputLock \(version) 更新日志")
                .font(.headline)

            if let attributedString {
                ScrollView {
                    HTMLTextView(attributedString: attributedString)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: 300)
            }

            Button("关闭") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(width: 400, height: 380)
        .task {
            attributedString = await loadNotes()
        }
    }

    private nonisolated func loadNotes() async -> NSAttributedString {
        guard let data = notes.data(using: .utf8) else {
            return NSAttributedString(string: notes)
        }
        return (try? NSAttributedString(data: data, options: [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ], documentAttributes: nil)) ?? NSAttributedString(string: notes)
    }
}

private struct HTMLTextView: NSViewRepresentable {
    let attributedString: NSAttributedString

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.backgroundColor = .clear
        view.drawsBackground = false
        view.isRichText = false
        view.textContainerInset = NSSize(width: 0, height: 4)
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        view.textStorage?.setAttributedString(attributedString)
    }
}
