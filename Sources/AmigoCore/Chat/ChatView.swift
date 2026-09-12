import SwiftUI

struct ChatView: View {
    @ObservedObject var session: ChatSession
    @State private var input = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if session.messages.isEmpty {
                            Text("随便聊点什么～它会慢慢记住你。")
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
                                            ? AnyShapeStyle(Color.accentColor.opacity(0.22))
                                            : AnyShapeStyle(.regularMaterial),
                                        in: RoundedRectangle(cornerRadius: 12))
                                if m.role != "user" { Spacer(minLength: 44) }
                            }.id(m.id)
                        }
                        if session.busy {
                            Text("在想…").font(.caption).foregroundStyle(.secondary)
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
                TextField("说点什么…", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(sendIt)
                Button("发送", action: sendIt)
                    .buttonStyle(.borderedProminent)
                    .disabled(session.busy || input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
        }
        .frame(minWidth: 340, minHeight: 400)
        .background(VisualEffectView().ignoresSafeArea())   // 毛玻璃
    }

    private func sendIt() {
        let t = input
        input = ""
        session.send(t)
    }
}
