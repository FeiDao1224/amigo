import SwiftUI

/// 首次启动引导：讲清楚它是什么 + 引导配模型（不配啥都干不了）
struct OnboardingView: View {
    let onConfigureModel: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "pawprint.circle.fill").font(.system(size: 54)).foregroundStyle(Color.orange.gradient)
            Text("欢迎养一只 Amigo").font(.title2.bold())
            Text("一只住在你桌面、会观察你状态、陪你干活、还被你调教性格的桌面搭子。")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 380)

            VStack(alignment: .leading, spacing: 12) {
                step("1", "配一个大模型", "填你的 API 端点 + Key，它才能真聊天、生成形象和动作")
                step("2", "选个形象 / 上传你自己的", "默认香蕉猫 / 看表鱼，或上传照片让 AI 生成专属像素形象")
                step("3", "调教性格 + 交互", "写它的人设，设定点击 / 拖动 / 对话触发什么动作")
            }.frame(maxWidth: 380)

            HStack(spacing: 12) {
                Button("先去配模型") { onConfigureModel() }.buttonStyle(.borderedProminent)
                Button("开始使用") { onDone() }
            }
            Text(License.enforced ? "免费试用 7 天，激活后长期使用。数据只存本机，不上传。"
                                   : "完全免费使用。你的 API Key 和数据只存本机，不上传。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(36).frame(width: 460)
    }

    private func step(_ n: String, _ t: String, _ d: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(.system(size: 13, weight: .semibold))
                Text(d).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
