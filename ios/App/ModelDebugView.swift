import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

struct ModelDebugView: View {
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

    var body: some View {
        Form {
            Section("调试模式") {
                Picker("模式", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                LabeledContent("本次模型", value: (usesPhoto ? configuration.visionModel : configuration.textModel).isEmpty
                               ? "待填写" : usesPhoto ? configuration.visionModel : configuration.textModel)
            }.disabled(running)
            if mode == .free {
                Section("本次系统提示词（可选）") {
                    TextField("输入要测试的系统提示词", text: $freePrompt, axis: .vertical)
                        .lineLimit(3...8)
                        .onChange(of: freePrompt) { _, value in
                            if value.count > 6000 { freePrompt = String(value.prefix(6000)) }
                        }
                }.disabled(running)
            }
            Section {
                TextField(mode == .meal ? "补充说明（可选）" : "输入测试文字", text: $text, axis: .vertical)
                    .lineLimit(3...8).accessibilityIdentifier("debug.text")
                    .onChange(of: text) { _, value in if value.count > 4000 { text = String(value.prefix(4000)) } }
                if mode == .metabolism {
                    Button("填入示例资料") {
                        text = #"{"sex":"male","age":30,"heightCM":175,"weightKG":70}"#
                    }
                } else {
                    PhotosPicker(selection: $imageSelection, matching: .images) {
                        Label(photo == nil ? "上传测试图片" : "更换测试图片", systemImage: "photo")
                    }
                    if loadingPhoto { ProgressView("正在准备图片…") }
                    if let photo, let preview = UIImage(data: photo) {
                        Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 140)
                        Button("移除图片", role: .destructive) { imageSelection = nil; self.photo = nil; photoError = "" }
                    }
                    if !photoError.isEmpty { Text(photoError).font(.footnote).foregroundStyle(.secondary) }
                }
            } header: { Text("测试输入") } footer: {
                Text(mode == .free ? "自由调试接受文字或图片。提交的内容会发送到所选 AI 服务。" :
                     "使用设置页当前的提示词草稿，并检查结果是否符合正式分析的格式。")
            }.disabled(running)
            Section {
                if running {
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        ProgressView("等待模型响应 · \(max(0, Int(context.date.timeIntervalSince(started)))) 秒")
                    }
                    Button("取消调试", role: .cancel) { task?.cancel() }
                } else {
                    Button("运行调试") { run() }.disabled(!canRun).accessibilityIdentifier("debug.run")
                }
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            if let result {
                Section("模型响应") {
                    LabeledContent("模型", value: result.model)
                    LabeledContent("耗时", value: "\(result.durationMs) ms")
                    if let valid = result.formatValid {
                        Label(valid ? "通过正式分析格式校验" : "未通过正式分析格式校验",
                              systemImage: valid ? "checkmark.circle" : "exclamationmark.circle")
                            .foregroundStyle(valid ? Theme.green : Theme.orange)
                    }
                    if let tokens = result.usage["total_tokens"] {
                        LabeledContent("Tokens", value: "\(tokens)")
                    }
                    if let finish = result.finishReason, finish != "stop" {
                        LabeledContent("结束原因", value: finish)
                    }
                    Text(result.output).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                        .accessibilityIdentifier("debug.output")
                }
            }
        }.scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("调试模型").navigationBarTitleDisplayMode(.inline)
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
