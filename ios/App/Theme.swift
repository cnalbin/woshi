import SwiftUI
import UIKit

enum Theme {
    static let green = Color(red: 0.035, green: 0.34, blue: 0.19)
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.067, green: 0.090, blue: 0.078, alpha: 1)
            : UIColor(red: 0.980, green: 0.969, blue: 0.945, alpha: 1)
    })
    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.106, green: 0.137, blue: 0.118, alpha: 1) : .white
    })
    static let softGreen = green.opacity(0.08)
    static let orange = Color(red: 0.94, green: 0.55, blue: 0.23)
    static let gutter: CGFloat = 18
    static let actionHeight: CGFloat = 50
    static let actionRadius: CGFloat = 14
}

struct Card<Content: View>: View {
    var surface: Color = Theme.card
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.035), lineWidth: 1))
            .shadow(color: .black.opacity(0.025), radius: 8, y: 3)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.appSkin) private var skin
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.actionLabel()
            .background(skin.buttonFill.opacity(!isEnabled ? 0.35 : configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: Theme.actionRadius))
            .foregroundStyle(.white)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.appSkin) private var skin
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let color: Color = configuration.role == .destructive ? .red : skin.accent
        configuration.label.actionLabel()
            .background(color.opacity(configuration.isPressed ? 0.08 : 0), in: RoundedRectangle(cornerRadius: Theme.actionRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.actionRadius).strokeBorder(color.opacity(isEnabled ? 1 : 0.25), lineWidth: 1))
            .foregroundStyle(color.opacity(isEnabled ? 1 : 0.4))
    }
}

struct BrandWordmark: View {
    @Environment(\.appSkin) private var skin
    var compact = true

    var body: some View {
        HStack(spacing: compact ? 4 : 8) {
            Image("BrandIcon").resizable().scaledToFit().frame(width: compact ? 32 : 66, height: compact ? 32 : 66)
                .clipShape(RoundedRectangle(cornerRadius: compact ? 9 : 18))
            Text("轻记").font(compact ? .headline : .largeTitle.bold())
        }.foregroundStyle(skin.accent).accessibilityElement(children: .ignore).accessibilityLabel("轻记")
    }
}

extension View {
    fileprivate func actionLabel() -> some View {
        font(.system(size: 16, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
            .padding(.horizontal, 8).frame(minWidth: 0, maxWidth: .infinity)
            .frame(height: Theme.actionHeight).contentShape(Rectangle())
    }

    func actionPreview(_ skin: AppSkin, filled: Bool) -> some View {
        actionLabel().foregroundStyle(filled ? .white : skin.accent)
            .background(filled ? skin.buttonFill : .clear, in: RoundedRectangle(cornerRadius: Theme.actionRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.actionRadius).strokeBorder(skin.accent, lineWidth: filled ? 0 : 1))
    }

    func pageActions<Actions: View>(@ViewBuilder _ actions: () -> Actions) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { PageActions(content: actions()) }
    }

    func subpageNavigation(title: String) -> some View {
        navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
    }
}

private struct PageActions<Content: View>: View {
    @Environment(\.appSkin) private var skin
    let content: Content

    var body: some View {
        content.padding(.horizontal, Theme.gutter).padding(.vertical, 10).background(skin.background)
    }
}

struct EqualActions: Layout {
    private let spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return CGSize(width: proposal.width ?? ideal * CGFloat(subviews.count) + spacing,
                      height: Theme.actionHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let width = max(0, (bounds.width - CGFloat(subviews.count - 1) * spacing) / CGFloat(subviews.count))
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(index) * (width + spacing), y: bounds.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(width: width, height: Theme.actionHeight))
        }
    }
}

struct PageSegments<Value: Equatable>: UIViewRepresentable {
    @Environment(\.appSkin) private var skin
    @Environment(\.isEnabled) private var isEnabled
    @Binding var selection: Value
    let options: [(String, Value)]
    var identifier: String? = nil

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: options.map { $0.0 })
        control.accessibilityIdentifier = identifier
        control.addTarget(context.coordinator, action: #selector(PageSegmentsCoordinator.changed(_:)), for: .valueChanged)
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.onChange = { index in
            if options.indices.contains(index) { selection = options[index].1 }
        }
        control.selectedSegmentIndex = options.firstIndex { $0.1 == selection } ?? UISegmentedControl.noSegment
        control.isEnabled = isEnabled
        control.selectedSegmentTintColor = UIColor(skin.buttonFill)
        control.backgroundColor = UIColor(Theme.card)
        control.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        control.setTitleTextAttributes([.foregroundColor: UIColor.label], for: .normal)
    }

    func makeCoordinator() -> PageSegmentsCoordinator { PageSegmentsCoordinator() }
}

final class PageSegmentsCoordinator: NSObject {
    var onChange: ((Int) -> Void)?
    @objc func changed(_ control: UISegmentedControl) { onChange?(control.selectedSegmentIndex) }
}

struct AnalysisStatusView: View {
    @Environment(\.appSkin) private var skin
    let progress: AnalysisProgress
    let startedAt: Date
    var history: [AnalysisProgress] = []
    var photoAnalysis = false
    let cancel: () -> Void
    var body: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(skin.accent)
                    .frame(width: 46, height: 46).background(skin.softAccent, in: RoundedRectangle(cornerRadius: 14))
                    .symbolEffect(.pulse, options: .repeating)
                VStack(alignment: .leading, spacing: 5) {
                    Text("AI 正在分析").font(.headline)
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text("已用时 \(max(0, Int(context.date.timeIntervalSince(startedAt)))) 秒")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Spacer()
                ProgressView().tint(skin.accent)
            }
            VStack(alignment: .leading, spacing: 12) {
                stage(photoAnalysis ? "发送照片" : "发送资料", index: 0)
                stage(photoAnalysis ? "识别食物与份量" : "估算静息代谢", index: 1)
                stage(photoAnalysis ? "整理热量结果" : "整理结果", index: 2)
            }
            Text(progress.message).font(.subheadline).foregroundStyle(skin.accent)
                .accessibilityIdentifier("analysis.progress")
            if !history.isEmpty {
                DisclosureGroup("本次处理记录") {
                    ForEach(Array(history.enumerated()), id: \.offset) { _, item in
                        Label(item.message, systemImage: item.stage == progress.stage ? "circle.inset.filled" : "checkmark.circle")
                            .font(.caption).foregroundStyle(.secondary).padding(.vertical, 2)
                    }
                }.font(.caption)
            }
            Button("取消分析", action: cancel).buttonStyle(OutlineButtonStyle())
                .accessibilityIdentifier("analysis.cancel")
                .accessibilityHint("取消网络请求，保留当前草稿")
        }
        .accessibilityElement(children: .contain)
    }
    private var activeStage: Int { progress.stage == "validating" ? 2 : ["received", "analyzing"].contains(progress.stage) ? 1 : 0 }
    private func stage(_ title: String, index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: index < activeStage ? "checkmark.circle.fill" : index == activeStage ? "circle.inset.filled" : "circle")
                .foregroundStyle(index <= activeStage ? skin.accent : .secondary)
            Text(title).font(.subheadline).foregroundStyle(index <= activeStage ? Color.primary : Color.secondary)
            Spacer()
            if index == activeStage { Text("进行中").font(.caption2).foregroundStyle(skin.accent) }
            else if index < activeStage { Text("已完成").font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

struct AIConsentView: View {
    @Environment(\.appSkin) private var skin
    let accept: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "sparkles").font(.system(size: 42)).foregroundStyle(skin.accent)
                    Text("使用 AI 前，请了解").font(.title.bold())
                    Card {
                        consentRow("本次上传", detail: "食物照片与补充说明", symbol: "camera")
                        Divider()
                        consentRow("代谢分析", detail: "年龄、性别、身高和体重", symbol: "waveform.path.ecg")
                        Divider()
                        consentRow("结果保存", detail: "核对食物、份量与热量后确认", symbol: "checkmark.square")
                    }
                    Text("仅在主动分析时发送给模型服务。Apple 健康活动数据和历史饮食不会发送给模型。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("DeepSeek 隐私政策", destination: URL(string: "https://cdn.deepseek.com/policies/zh-CN/deepseek-privacy-policy.html")!)
                        .frame(minHeight: 44)
                }.padding(Theme.gutter)
            }.background(skin.background)
            .navigationTitle("AI 使用说明").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) } }
            .pageActions {
                EqualActions {
                    Button("暂不使用", role: .cancel) { dismiss() }.buttonStyle(OutlineButtonStyle())
                    Button("同意并继续") { accept(); dismiss() }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("ai.consent.accept")
                }
            }
        }
    }

    private func consentRow(_ title: String, detail: String, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(skin.accent).frame(width: 36, height: 36)
                .background(skin.softAccent, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
