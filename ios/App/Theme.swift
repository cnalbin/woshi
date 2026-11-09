import SwiftUI

enum Theme {
    static let green = Color(red: 0.035, green: 0.34, blue: 0.19)
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemGroupedBackground : UIColor(red: 0.985, green: 0.976, blue: 0.958, alpha: 1)
    })
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let softGreen = green.opacity(0.08)
    static let orange = Color(red: 0.94, green: 0.55, blue: 0.23)
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.035), lineWidth: 1))
            .shadow(color: .black.opacity(0.025), radius: 8, y: 3)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(Theme.green.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
    }
}

struct AnalysisStatusView: View {
    let progress: AnalysisProgress
    let startedAt: Date
    var history: [AnalysisProgress] = []
    let cancel: () -> Void
    var body: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(Theme.green)
                    .frame(width: 46, height: 46).background(Theme.softGreen, in: RoundedRectangle(cornerRadius: 14))
                    .symbolEffect(.pulse, options: .repeating)
                VStack(alignment: .leading, spacing: 5) {
                    Text("AI 正在分析").font(.headline)
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text("已用时 \(max(0, Int(context.date.timeIntervalSince(startedAt)))) 秒")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Spacer()
                ProgressView().tint(Theme.green)
            }
            VStack(alignment: .leading, spacing: 12) {
                stage("发送资料", index: 0)
                stage("识别与估算", index: 1)
                stage("整理结果", index: 2)
            }
            Text(progress.message).font(.subheadline).foregroundStyle(Theme.green)
                .accessibilityIdentifier("analysis.progress")
            Text("显示服务器返回的处理阶段。完成后可查看估算依据；照片结果经你确认后才保存。")
                .font(.caption).foregroundStyle(.secondary)
            if !history.isEmpty {
                DisclosureGroup("本次处理记录") {
                    ForEach(Array(history.enumerated()), id: \.offset) { _, item in
                        Label(item.message, systemImage: "checkmark.circle")
                            .font(.caption).foregroundStyle(.secondary).padding(.vertical, 2)
                    }
                }.font(.caption)
            }
            Button("取消分析", action: cancel).font(.subheadline.weight(.medium))
                .accessibilityIdentifier("analysis.cancel")
                .accessibilityHint("取消网络请求，保留当前草稿")
        }
        .accessibilityElement(children: .contain)
    }
    private var activeStage: Int { progress.stage == "validating" ? 2 : ["received", "analyzing"].contains(progress.stage) ? 1 : 0 }
    private func stage(_ title: String, index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: index < activeStage ? "checkmark.circle.fill" : index == activeStage ? "circle.inset.filled" : "circle")
                .foregroundStyle(index <= activeStage ? Theme.green : .secondary)
            Text(title).font(.subheadline).foregroundStyle(index <= activeStage ? Color.primary : Color.secondary)
            Spacer()
            if index == activeStage { Text("进行中").font(.caption2).foregroundStyle(Theme.green) }
            else if index < activeStage { Text("已完成").font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

struct AIConsentView: View {
    let accept: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "sparkles").font(.system(size: 44)).foregroundStyle(Theme.green)
                    Text("使用 AI 前，请了解").font(.largeTitle.bold())
                    Text("拍照分析会将本次食物照片和补充说明，通过所连接的服务器发送给你配置的模型服务。代谢分析仅发送年龄、性别、身高和体重。不会发送苹果健康活动数据或历史饮食。")
                    Text("仅在你主动点击分析时发送给模型服务。账号数据自动同步到所连接的服务器。模型服务商的处理与保留政策以其条款为准。")
                    Text("AI 结果是估算，不能精确测量份量、油脂或代谢。保存前请核对食物、份量与热量。")
                    Link("查看 DeepSeek 隐私政策", destination: URL(string: "https://cdn.deepseek.com/policies/zh-CN/deepseek-privacy-policy.html")!)
                    Button("同意并继续") { accept(); dismiss() }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("ai.consent.accept")
                    Button("暂不使用", role: .cancel) { dismiss() }.frame(maxWidth: .infinity)
                }.padding(24)
            }
            .navigationTitle("AI 使用说明").navigationBarTitleDisplayMode(.inline)
        }
    }
}
