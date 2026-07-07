import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @ObservedObject var session: ChatSession
    @State private var input = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if session.messages.isEmpty {
                            Text("跟阿豆随便聊点什么～它会慢慢记住你。也可以把文件拖进来让它帮你看。")
                                .font(.caption).foregroundStyle(.secondary).padding(.top, 10)
                        }
                        ForEach(session.messages) { m in
                            HStack {
                                if m.role == "user" { Spacer(minLength: 44) }
                                Text(m.content)
                                    .font(.system(size: 13))
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 11).padding(.vertical, 7)
                                    .background(
                                        m.role == "user"
                                            ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                                            : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)),
                                        in: RoundedRectangle(cornerRadius: 12))
                                if m.role != "user" { Spacer(minLength: 44) }
                            }.id(m.id)
                        }
                        if session.busy {
                            Text("阿豆在想…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: session.messages.count) { _ in
                    if let last = session.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextField("跟阿豆说点什么…", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(sendIt)
                Button("发送", action: sendIt)
                    .buttonStyle(.borderedProminent)
                    .disabled(session.busy || input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
        }
        .frame(minWidth: 340, minHeight: 400)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let p = providers.first else { return false }
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                if let url { DispatchQueue.main.async { session.sendFile(url) } }
            }
            return true
        }
    }

    private func sendIt() {
        let t = input
        input = ""
        session.send(t)
    }
}
