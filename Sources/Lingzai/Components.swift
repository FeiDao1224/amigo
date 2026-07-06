import SwiftUI
import AppKit

// 毛玻璃背景（桌面透过来）
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

// 整图程序动画：按状态 + 时间算 位移/缩放/旋转
struct PetMotion: ViewModifier {
    let state: PetState
    let time: TimeInterval
    func body(content: Content) -> some View {
        var dx = 0.0, dy = 0.0, sx = 1.0, sy = 1.0, rot = 0.0
        let t = time
        switch state {
        case .idle:
            dy = sin(t * 2.2) * 2.5
            sy = 1 + sin(t * 1.6) * 0.02
        case .talk:
            dy = sin(t * 10) * 2.6
            sy = 1 + sin(t * 10) * 0.03
        case .happy:
            dy = -abs(sin(t * 9)) * 11
            sy = 1 + abs(sin(t * 9)) * 0.06
        case .shocked:
            dx = sin(t * 42) * 4
            sx = 1.05; sy = 1.05
        case .bored:
            rot = 6; dy = 3
        case .sleep:
            sy = 1 + sin(t * 1.0) * 0.03
        case .dragged:
            rot = 7
        case .hop:
            dy = -abs(sin(t * 7)) * 14
            sy = 1 + abs(sin(t * 7)) * 0.06
        case .wiggle:
            rot = sin(t * 18) * 6
        case .stretch:
            sy = 1 + abs(sin(t * 4)) * 0.12
            sx = 1 - abs(sin(t * 4)) * 0.05
        case .lean:
            rot = sin(t * 4) * 9
        }
        return content
            .rotationEffect(.degrees(rot), anchor: .bottom)
            .scaleEffect(x: sx, y: sy, anchor: .bottom)
            .offset(x: dx, y: dy)
    }
}

// 三角形（猫耳 / 鼻子 / 气泡尾巴）
struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// 设置：区块标题
struct SectionHeader: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text).font(.system(size: 20, weight: .bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8).padding(.bottom, 4)
    }
}

// 设置：分组卡片
struct GroupCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.06)))
    }
}

// 设置：一行（标题 + 副标题 + 右侧控件）
struct GRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let s = subtitle {
                    Text(s).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}

// 卡片内分隔线
struct RowDivider: View {
    var body: some View { Divider().padding(.leading, 14).opacity(0.5) }
}

// 侧栏一项（彩色图标 + 标题 + 副标题）
struct SidebarRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let selected: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 27, height: 27)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(selected ? Color.primary.opacity(0.10) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
