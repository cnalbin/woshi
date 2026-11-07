import SwiftUI

enum Theme {
    static let green = Color(red: 0.035, green: 0.34, blue: 0.19)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let softGreen = Color.green.opacity(0.09)
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(Theme.green.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(.white)
    }
}

struct AnalysisStatusView: View {
    let progress: AnalysisProgress
    let startedAt: Date
    let cancel: () -> Void
    var body: some View {
        Card {
            HStack(spacing: 14) {
                ProgressView().tint(Theme.green).scaleEffect(1.2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(progress.message).font(.headline)
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text("已等待 \(max(0, Int(context.date.timeIntervalSince(startedAt)))) 秒 · 通常需要一些时间")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            HStack {
                Label("资料已接收", systemImage: progress.stage == "uploading" ? "circle" : "checkmark.circle.fill")
                Spacer()
                Label("AI 分析", systemImage: progress.stage == "validating" ? "checkmark.circle.fill" : "sparkles")
                Spacer()
                Label("结果校验", systemImage: progress.stage == "validating" ? "checkmark.circle.fill" : "circle")
            }
            .font(.caption2).foregroundStyle(Theme.green)
            Text("等待时不会自动保存。完成后展示估算依据，方便你核对。")
                .font(.caption).foregroundStyle(.secondary)
            Button("取消分析", action: cancel).font(.subheadline)
                .accessibilityHint("取消网络请求，保留当前草稿")
        }
        .accessibilityElement(children: .contain)
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
                    Text("拍照分析会将本次食物照片和补充说明，通过你配置的后端发送给 DeepSeek。代谢分析仅发送年龄、性别、身高和体重。不会发送苹果健康活动数据或历史饮食。")
                    Text("App 不在服务端保存照片和资料，也不主动将照片用于训练；模型服务商的处理与保留政策以其条款为准。仅在你主动点击分析时发送。")
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
