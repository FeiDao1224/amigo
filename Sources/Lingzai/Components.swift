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
        }
        return content
            .rotationEffect(.degrees(rot), anchor: .bottom)
            .scaleEffect(x: sx, y: sy, anchor: .bottom)
            .offset(x: dx, y: dy)
    }
}

// 走/跑的程序位移（没生成对应动作帧时的兜底反馈，叠加在当前帧上）
struct MoveMotion: ViewModifier {
    let kind: Int          // 0 无 / 1 走 / 2 跑
    let time: TimeInterval
    func body(content: Content) -> some View {
        var dx = 0.0, dy = 0.0, rot = 0.0
        let t = time
        switch kind {
        case 1: dx = sin(t * 6) * 3;  dy = -abs(sin(t * 12)) * 2; rot = sin(t * 6) * 2
        case 2: dx = sin(t * 11) * 6; dy = -abs(sin(t * 20)) * 4; rot = sin(t * 11) * 4
        default: break
        }
        return content.rotationEffect(.degrees(rot), anchor: .bottom).offset(x: dx, y: dy)
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

// 思考云：一圈外凸的椭圆 + 中心椭圆，填充即并集（无内部线）
struct CloudShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let cx = r.midX, cy = r.midY, rx = r.width / 2, ry = r.height / 2
        let base = min(rx, ry), n = 8
        for i in 0..<n {
            let ang = CGFloat(i) / CGFloat(n) * 2 * .pi - .pi / 2
            let rr = base * (0.62 + 0.22 * abs(sin(CGFloat(i) * 2.1)))
            let ex = cx + (rx - rr * 0.72) * cos(ang)
            let ey = cy + (ry - rr * 0.72) * sin(ang)
            p.addEllipse(in: CGRect(x: ex - rr, y: ey - rr, width: rr * 2, height: rr * 2))
        }
        p.addEllipse(in: CGRect(x: r.minX + rx * 0.18, y: r.minY + ry * 0.18,
                                width: r.width * 0.64, height: r.height * 0.64))
        return p
    }
}

// 思考云容器：白填充 + 深色描边（描边=深色云略大垫在后面）
struct ThoughtCloud<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, 24).padding(.vertical, 20)
            .background(
                ZStack {
                    CloudShape().fill(Color(white: 0.24)).padding(-2.5)
                    CloudShape().fill(.white)
                }
            )
    }
}

// 思考气泡下方那串小圆（从左下冒出）
struct ThoughtDots: View {
    var body: some View {
        VStack(spacing: 3) { dot(13); dot(8); dot(5) }.offset(x: -34)
    }
    private func dot(_ s: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color(white: 0.24)).frame(width: s + 2.5, height: s + 2.5)
            Circle().fill(.white).frame(width: s, height: s)
        }
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
