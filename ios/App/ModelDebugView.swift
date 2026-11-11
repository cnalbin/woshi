import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

struct ModelDebugView: View {
    @Environment(\.appSkin) private var skin
    let configuration: AIConfigurationDraft
    let service: ServiceConfiguration

    private enum Mode: String, CaseIterable, Identifiable {
        case free, meal, metabolism
        var id: String { rawValue }
        var label: String {
            switch self {
            case .free: return "自由"
            case .meal: return "拍照"
            case .metabolism: return "代谢"
            }
        }
    }

    private struct Input: Encodable {
        let configuration: AIConfigurationDraft
        let mode: String
        let prompt: String
        let text: String
        let imageBase64: String?
    }

    private struct Result: Decodable {
        let output: String
        let model: String
        let durationMs: Int
        let usage: [String: Int]
        let finishReason: String?
        let formatValid: Bool?
    }

    @State private var mode = Mode.free
    @State private var freePrompt = ""
    @State private var text = ""
    @State private var imageSelection: PhotosPickerItem?
    @State private var photo: Data?
    @State private var loadingPhoto = false
    @State private var photoError = ""
    @State private var running = false
    @State private var task: Task<Void, Never>?
    @State private var started = Date()
    @State private var result: Result?
    @State private var error = ""

    private var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var usesPhoto: Bool { mode != .metabolism && photo != nil }
    private var canRun: Bool {
        !loadingPhoto && (mode == .meal ? usesPhoto : hasText || usesPhoto)
    }
    private var model: String { mode == .meal || usesPhoto ? configuration.visionModel : configuration.textModel }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("调试模型").font(.title.bold()).accessibilityAddTraits(.isHeader)
                Picker("模式", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).disabled(running)
                Card { LabeledContent("模型", value: model.isEmpty ? "待填写" : model) }
                VStack(alignment: .leading, spacing: 12) {
                    if mode == .free {
                        Card {
                            Text("本次系统提示词（可选）").font(.caption).foregroundStyle(.secondary)
                            TextField("输入要测试的系统提示词", text: $freePrompt, axis: .vertical)
                                .lineLimit(3...8)
                                .onChange(of: freePrompt) { _, value in
                                    if value.count > 6000 { freePrompt = String(value.prefix(6000)) }
                                }
                        }
                    }
                    if mode != .metabolism { photoInput }
                    Card {
                        TextField(mode == .meal ? "补充说明（可选）" : "输入测试文字", text: $text, axis: .vertical)
                            .lineLimit(3...8).accessibilityIdentifier("debug.text")
                            .onChange(of: text) { _, value in if value.count > 4000 { text = String(value.prefix(4000)) } }
                        if mode == .metabolism {
                            Button("填入示例资料") { text = #"{"sex":"male","age":30,"heightCM":175,"weightKG":70}"# }
                        }
                    }
                }.disabled(running)
                if running {
                    Card {
                        TimelineView(.periodic(from: started, by: 1)) { context in
                            ProgressView("等待模型响应 · \(max(0, Int(context.date.timeIntervalSince(started)))) 秒")
                        }
                        Button("取消调试", role: .cancel) { task?.cancel() }
                    }
                } else {
                    Button("运行调试") { run() }.buttonStyle(PrimaryButtonStyle()).disabled(!canRun)
                        .accessibilityIdentifier("debug.run")
                }
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled) }
                if let result { resultCard(result) }
                Text(mode == .free ? "提交的内容会发送到所选 AI 服务。" : "使用当前提示词并校验正式分析格式。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(18)
        }.background(skin.background).brandedNavigation(title: "调试模型")
            .task(id: imageSelection) {
                guard let imageSelection else { loadingPhoto = false; return }
                loadingPhoto = true; photo = nil; photoError = ""
                defer { if self.imageSelection == imageSelection { loadingPhoto = false } }
                do {
                    guard let data = try await imageSelection.loadTransferable(type: Data.self) else {
                        throw AIError.message("无法读取所选图片。")
                    }
                    let resized = await Task.detached(priority: .userInitiated) { Self.compress(data) }.value
                    try Task.checkCancellation()
                    guard let resized else { throw AIError.message("图片无法处理，请换一张。") }
                    photo = resized
                } catch is CancellationError {} catch {
                    if self.imageSelection == imageSelection { photoError = error.localizedDescription }
                }
            }
            .onDisappear { task?.cancel() }
    }

    private var photoInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let photo, let preview = UIImage(data: photo) {
                    Image(uiImage: preview).resizable().scaledToFill().frame(width: 148, height: 126)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Spacer()
                VStack(spacing: 8) {
                    PhotosPicker(selection: $imageSelection, matching: .images) {
                        Label(photo == nil ? "上传测试图片" : "更换图片", systemImage: "photo")
                    }.buttonStyle(.bordered)
                    if photo != nil {
                        Button("移除图片", role: .destructive) { imageSelection = nil; photo = nil; photoError = "" }.font(.caption)
                    }
                }
            }
            if loadingPhoto { ProgressView("正在准备图片…") }
            if !photoError.isEmpty { Text(photoError).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    private func resultCard(_ result: Result) -> some View {
        Card {
            HStack {
                Text("调试结果").font(.headline)
                Spacer()
                if let valid = result.formatValid {
                    Label(valid ? "格式校验通过" : "格式校验失败",
                          systemImage: valid ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.caption).foregroundStyle(valid ? skin.accent : Theme.orange)
                }
            }
            if mode == .free || result.formatValid != true {
                rawOutput(result)
            } else {
                if let meal = try? JSONDecoder().decode(MealAnalysis.self, from: Data(result.output.utf8)) {
                    ForEach(Array(meal.items.enumerated()), id: \.offset) { _, item in
                        Text("\(item.name) · 约 \(item.estimatedGrams.formatted()) g · \(item.estimatedKcal.formatted()) kcal")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                DisclosureGroup("查看模型原文") { rawOutput(result) }.font(.subheadline)
            }
            HStack {
                Text("耗时 \((Double(result.durationMs) / 1000).formatted(.number.precision(.fractionLength(0...1)))) 秒")
                if let tokens = result.usage["total_tokens"] { Text("· \(tokens) Token") }
                if let finish = result.finishReason, finish != "stop" { Text("· \(finish)") }
            }.font(.caption).foregroundStyle(.secondary)
        }
    }

    private func rawOutput(_ result: Result) -> some View {
        Text(result.output).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
            .accessibilityIdentifier("debug.output")
    }

    private func run() {
        guard !running, canRun else { return }
        let prompt: String
        switch mode {
        case .free: prompt = freePrompt
        case .meal: prompt = configuration.mealPrompt
        case .metabolism: prompt = configuration.metabolismPrompt
        }
        var connection = configuration
        connection.mealPrompt = ""
        connection.metabolismPrompt = ""
        let image = usesPhoto ? photo : nil
        let mode = mode.rawValue
        let text = text
        running = true; error = ""; result = nil; started = Date()
        task = Task {
            defer { running = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try JSONEncoder().encode(Input(configuration: connection, mode: mode, prompt: prompt,
                                                   text: text, imageBase64: image?.base64EncodedString()))
                }.value
                try Task.checkCancellation()
                let response = try await CloudClient(configuration: service).request("v1/ai/debug", method: "POST",
                    data: data, maximum: 300_000, timeout: 200)
                try Task.checkCancellation()
                result = try JSONDecoder().decode(Result.self, from: response)
            } catch is CancellationError { self.error = "已取消调试，输入已保留。" }
            catch let failure as URLError where failure.code == .cancelled { self.error = "已取消调试，输入已保留。" }
            catch { self.error = error.localizedDescription }
        }
    }

    nonisolated private static func compress(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(encoder, image, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        return CGImageDestinationFinalize(encoder) && output.length <= 4_000_000 ? output as Data : nil
    }
}
