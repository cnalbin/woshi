import SwiftUI
import PhotosUI
import UIKit

struct MealEditor: View {
    @Environment(\.appSkin) private var skin
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let existing: Meal?
    let initialDate: Date
    let analysis: MealAnalysis?
    let photoData: Data?
    let onSaved: (() -> Void)?
    @State private var recordID = UUID()
    @State private var consumedAt = Date()
    @State private var kind = MealKind.suggested()
    @State private var items: [FoodItem] = []
    @State private var fraction = 1.0
    @State private var editingFood: FoodItem?
    @State private var initialized = false
    @State private var saving = false
    @State private var error: String?
    @State private var deleteConfirmation = false
    @State private var previewImage: UIImage?

    init(existing: Meal? = nil, initialDate: Date = Date(), analysis: MealAnalysis? = nil,
         photoData: Data? = nil, onSaved: (() -> Void)? = nil) {
        self.existing = existing; self.initialDate = initialDate; self.analysis = analysis
        self.photoData = photoData; self.onSaved = onSaved
    }

    private var total: Double { items.reduce(0) { $0 + $1.kcal } * fraction }
    private var valid: Bool { !items.isEmpty && items.count <= 30 && items.allSatisfy(\.isValid) && consumedAt <= Date() }

    var body: some View {
        NavigationStack {
            List {
                if let image = previewImage {
                    Section {
                        Image(uiImage: image).resizable().scaledToFill().frame(height: 190).frame(maxWidth: .infinity).clipped()
                            .listRowInsets(EdgeInsets())
                    }
                }
                Section {
                    Picker("餐次", selection: $kind) { ForEach(MealKind.allCases) { Text($0.label).tag($0) } }
                    DatePicker("吃饭时间", selection: $consumedAt, in: ...Date())
                }
                Section {
                    ForEach(items) { item in
                        Button { editingFood = item } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.name).foregroundStyle(.primary)
                                    if let grams = item.grams { Text("\(grams.formatted(.number.precision(.fractionLength(0...1)))) 克").font(.caption).foregroundStyle(.secondary) }
                                    else { Text("未填写克数").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Text("\(Int(item.kcal.rounded())) kcal").foregroundStyle(.primary).monospacedDigit()
                                Image(systemName: "pencil").foregroundStyle(.secondary)
                            }
                        }
                    }.onDelete { items.remove(atOffsets: $0) }
                    Button { editingFood = FoodItem(name: "", kcal: 0) } label: { Label("添加食物", systemImage: "plus") }
                        .accessibilityIdentifier("food.add")
                        .disabled(items.count >= 30)
                } header: { Text("食物与热量") }
                Section {
                    Picker("实际吃了", selection: $fraction) {
                        Text("全部").tag(1.0); Text("1/2").tag(0.5); Text("1/4").tag(0.25)
                    }.pickerStyle(.segmented)
                } footer: {
                    Text(analysis?.portionBasis == "consumed"
                         ? "AI 已按你说明的实际摄入估算。若列表与实际相符，请保留「全部」，避免重复折算。"
                         : "食物列表显示整份，保存时按所选比例折算。已保存记录再次打开时，列表显示上次实际吃下的量。")
                }
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("本次摄入").font(.subheadline.weight(.semibold))
                        Text("\(Int(total.rounded())) kcal").font(.title2.bold()).foregroundStyle(skin.accent)
                    }.padding(.vertical, 5)
                }.listRowBackground(skin.membershipBackground)
                if let summary = analysis?.summary ?? existing?.summary, !summary.isEmpty {
                    Section("估算依据") {
                        Label("AI 估算，保存前请核对", systemImage: "sparkles").foregroundStyle(skin.accent)
                        Text(summary)
                        ForEach(Array((analysis?.assumptions ?? existing?.assumptions ?? []).enumerated()), id: \.offset) { _, value in
                            Text(value).font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(Array((analysis?.questions ?? []).enumerated()), id: \.offset) { _, value in
                            Label(value, systemImage: "questionmark.circle").font(.subheadline)
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.subheadline) } }
                if existing != nil {
                    Section { Button("删除这条记录", role: .destructive) { deleteConfirmation = true } }
                }
            }
            .scrollContentBackground(.hidden).background(skin.background)
            .navigationTitle(existing != nil ? "编辑饮食记录" : analysis == nil ? "手动记餐" : "核对食物与份量").navigationBarTitleDisplayMode(.inline)
            .pageActions {
                Button(saving ? "正在保存…" : existing == nil ? "确认并保存" : "保存修改") { save() }.buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("meal.save")
                    .disabled(!valid || saving || store.storageUnavailable)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .onAppear { initialize() }
            .task {
                if let photoData { previewImage = UIImage(data: photoData) }
                else if let existing, let url = store.photoURL(for: existing) {
                    previewImage = await Task.detached(priority: .userInitiated) { UIImage(contentsOfFile: url.path) }.value
                }
            }
            .sheet(item: $editingFood) { food in
                FoodEditor(food: food) { updated in
                    if let index = items.firstIndex(where: { $0.id == updated.id }) { items[index] = updated }
                    else { items.append(updated) }
                }
            }
            .confirmationDialog("删除这条饮食记录及本机照片？", isPresented: $deleteConfirmation, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    guard let existing else { return }
                    do { try store.deleteMeal(existing); dismiss() } catch { self.error = error.localizedDescription }
                }
            }
        }
    }

    private func initialize() {
        guard !initialized else { return }
        initialized = true
        if let existing {
            recordID = existing.id; consumedAt = existing.consumedAt; kind = existing.kind; items = existing.items
        } else {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.hour, .minute], from: Date())
            consumedAt = min(calendar.date(bySettingHour: components.hour ?? 12, minute: components.minute ?? 0, second: 0, of: initialDate) ?? initialDate, Date())
            kind = .suggested(at: consumedAt)
            items = analysis?.items.map(\.foodItem) ?? []
        }
    }

    private func save() {
        guard !saving, valid else { return }
        saving = true
        defer { saving = false }
        let meal = Meal(id: recordID, consumedAt: consumedAt, kind: kind, items: items.map { $0.scaled(by: fraction) },
            source: existing?.source ?? (analysis == nil ? "manual" : "ai"),
            summary: analysis?.summary ?? existing?.summary ?? "",
            assumptions: analysis?.assumptions ?? existing?.assumptions ?? [], photoFilename: existing?.photoFilename,
            createdAt: existing?.createdAt ?? Date())
        do { try store.saveMeal(meal, photo: photoData); onSaved?(); dismiss() }
        catch { self.error = "保存失败，草稿仍在：\(error.localizedDescription)" }
    }
}

struct FoodEditor: View {
    @Environment(\.appSkin) private var skin
    let food: FoodItem
    let onSave: (FoodItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var grams = ""
    @State private var kcal = ""
    private var updated: FoodItem? {
        guard let energy = NumberText.parse(kcal) else { return nil }
        let weight: Double?
        if grams.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { weight = nil }
        else { guard let parsed = NumberText.parse(grams) else { return nil }; weight = parsed }
        let value = FoodItem(id: food.id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), grams: weight, kcal: energy)
        return value.isValid ? value : nil
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Card {
                        foodField("食物名称") { TextField("例如：米饭", text: $name).accessibilityIdentifier("food.name") }
                        foodField("份量（可选）") {
                            HStack { TextField("克数", text: $grams).keyboardType(.decimalPad); Text("克").foregroundStyle(.secondary) }
                        }
                        foodField("热量") {
                            HStack { TextField("必填", text: $kcal).keyboardType(.decimalPad).accessibilityIdentifier("food.kcal"); Text("kcal").foregroundStyle(.secondary) }
                        }
                    }
                    Label("可参考包装营养标签。", systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
                if let base = food.grams, base > 0, let next = NumberText.parse(grams), next > 0 {
                    Card {
                        Button("按新克数同比换算热量") { kcal = (food.kcal * next / base).formatted(.number.grouping(.never).precision(.fractionLength(0...1))) }
                        Text("按相同食物配方和热量密度换算。也可直接修改热量。").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                }.padding(Theme.gutter)
            }
            .background(skin.background).scrollDismissesKeyboard(.interactively)
            .navigationTitle(food.name.isEmpty ? "添加食物" : "编辑食物").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .pageActions {
                Button("保存食物") { if let updated { onSave(updated); dismiss() } }
                    .buttonStyle(PrimaryButtonStyle()).disabled(updated == nil).accessibilityIdentifier("food.done")
            }
            .onAppear {
                name = food.name; grams = food.grams.map { $0.formatted(.number.grouping(.never).precision(.fractionLength(0...1))) } ?? ""
                kcal = food.name.isEmpty ? "" : food.kcal.formatted(.number.grouping(.never).precision(.fractionLength(0...1)))
            }
        }
    }

    private func foodField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            content().padding(.horizontal, 12).frame(minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.25)))
        }
    }
}

struct PhotoMealView: View {
    @Environment(\.appSkin) private var skin
    @State private var showQuota = false
    @State private var manualAfterQuota = false
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var membership: MembershipModel
    @Environment(\.dismiss) private var dismiss
    let initialDate: Date
    @State private var selection: PhotosPickerItem?
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var imageData: Data?
    @State private var preview: UIImage?
    @State private var note = ""
    @State private var loadingImage = false
    @State private var running = false
    @State private var task: Task<Void, Never>?
    @State private var progress = AnalysisProgress(stage: "uploading", message: "正在发送本次照片")
    @State private var history: [AnalysisProgress] = []
    @State private var started = Date()
    @State private var analysis: MealAnalysis?
    @State private var error: String?
    @State private var cancelled = false
    @State private var consent = false
    @State private var review = false
    @State private var saved = false
    @State private var showModel = false
    @State private var pendingQuestions: [MealClarification] = []
    @State private var choices: [Int: MealAnswerChoice] = [:]
    @State private var customAnswers: [Int: String] = [:]
    @State private var submittedAnswers: [MealClarificationAnswer] = []
    @State private var showConfirmation = false
    @State private var continueAfterConfirmation = false
    @State private var analysisID = UUID()

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if running || analysis != nil, let preview {
                            HStack(spacing: 12) {
                                Image(uiImage: preview).resizable().scaledToFill().frame(width: 80, height: 70)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                if running { Text("根据本次照片估算食物与热量").font(.subheadline).foregroundStyle(.secondary) }
                                else { Label("估算完成", systemImage: "checkmark.circle.fill").foregroundStyle(skin.accent) }
                            }
                        } else {
                        photoPreview
                        EqualActions {
                            Button { showCamera = true } label: { Label("拍摄照片", systemImage: "camera") }
                                .buttonStyle(OutlineButtonStyle()).disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                                .accessibilityIdentifier("photo.camera")
                            Button { showLibrary = true } label: { Label("从相册选择", systemImage: "photo") }
                                .buttonStyle(OutlineButtonStyle()).accessibilityIdentifier("photo.library")
                        }.disabled(running || loadingImage)
                        if loadingImage { ProgressView("正在准备照片…").font(.caption) }
                        Card {
                            Text("补充说明").font(.subheadline.weight(.semibold))
                            TextField("例如：半碗米饭，鸡肉去皮，汤没喝", text: $note, axis: .vertical)
                                .font(.subheadline).lineLimit(2...4).disabled(running || !pendingQuestions.isEmpty)
                                .accessibilityIdentifier("photo.note")
                                .onChange(of: note) { _, value in if value.count > 500 { note = String(value.prefix(500)) } }
                            Text("可填写份量、做法和实际吃下的比例").font(.caption2).foregroundStyle(.secondary)
                        }
                        }
                        if running {
                            AnalysisStatusView(progress: progress, startedAt: started, history: history) { task?.cancel() }
                                .id("photo.status")
                        } else if !pendingQuestions.isEmpty {
                            Card {
                                Label("还需确认 \(pendingQuestions.count) 项", systemImage: "questionmark.bubble")
                                    .font(.headline)
                                Button("查看待确认项") { showConfirmation = true }
                                    .accessibilityIdentifier("photo.confirmation.open")
                                if !submittedAnswers.isEmpty {
                                    Button("按已填答案重试") { run(answers: submittedAnswers) }.buttonStyle(PrimaryButtonStyle())
                                }
                                Button("重新识别照片") { resetConfirmation(); begin() }.font(.caption)
                            }
                        }
                        if cancelled && !running {
                            Card {
                                Label("已取消，照片与说明已保留", systemImage: "pause.circle").font(.subheadline.weight(.medium))
                                    .accessibilityIdentifier("photo.cancelled")
                                Button("改为手动记录") { analysis = nil; review = true }.font(.subheadline)
                            }
                        }
                        if let error, !running {
                            Card {
                                Label("这次分析未完成", systemImage: "exclamationmark.circle").font(.headline).foregroundStyle(Theme.orange)
                                Text(error).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                                Button("检查模型设置") { showModel = true }.font(.subheadline).frame(minHeight: 44)
                            }
                        }
                        if let analysis, !running { resultCard(analysis).id("photo.result") }
                    }.padding(18)
                }.background(skin.background)
                    .onChange(of: running) { _, active in
                        if active { withAnimation { proxy.scrollTo("photo.status", anchor: .bottom) } }
                    }
                    .onChange(of: analysis != nil) { _, ready in
                        if ready { withAnimation { proxy.scrollTo("photo.result", anchor: .bottom) } }
                    }
            }.navigationTitle("拍照记餐").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
                .pageActions {
                    if !running && pendingQuestions.isEmpty {
                        if analysis != nil {
                            VStack(spacing: 0) {
                                Button("核对食物与份量") { review = true }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("photo.review")
                                Button("重新分析") { begin() }.frame(minHeight: 44).accessibilityIdentifier("photo.start")
                            }
                        } else if error != nil {
                            EqualActions {
                                Button("手动记录") { review = true }.buttonStyle(OutlineButtonStyle())
                                Button("重新分析") { begin() }.buttonStyle(PrimaryButtonStyle())
                                    .disabled(imageData == nil || loadingImage).accessibilityIdentifier("photo.start")
                            }
                        } else {
                            Button(cancelled ? "重新分析" : "开始 AI 分析") { begin() }
                                .buttonStyle(PrimaryButtonStyle()).disabled(imageData == nil || loadingImage)
                                .accessibilityIdentifier("photo.start")
                        }
                    }
                }
                .sheet(isPresented: $showQuota, onDismiss: {
                    if manualAfterQuota { manualAfterQuota = false; review = true }
                }) {
                    NavigationStack {
                        BuiltInModelView(onManual: { manualAfterQuota = true; showQuota = false })
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { showQuota = false } } }
                    }
                }
                .photosPicker(isPresented: $showLibrary, selection: $selection, matching: .images)
                .task(id: selection) {
                    guard let selection else { return }
                    do {
                        guard let data = try await selection.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                            throw AIError.message("无法读取这张照片，请换一张。")
                        }
                        try Task.checkCancellation()
                        await setImage(image)
                    } catch is CancellationError {} catch { self.error = error.localizedDescription }
                }
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-uiTestPhoto"), let image = UIImage(named: "BrandIcon") {
                        await setImage(image)
                    }
                    #endif
                }
                .fullScreenCover(isPresented: $showCamera) { CameraPicker { image in Task { await setImage(image) } } }
                .sheet(isPresented: $consent) {
                    AIConsentView {
                        do { try store.setAIConsent(true); run() } catch { self.error = error.localizedDescription }
                    }
                }
                .sheet(isPresented: $review, onDismiss: { if saved { dismiss() } }) {
                    MealEditor(initialDate: initialDate, analysis: analysis, photoData: imageData) { saved = true }
                }
                .sheet(isPresented: $showConfirmation, onDismiss: resumeAfterConfirmation) {
                    MealConfirmationView(questions: pendingQuestions, choices: $choices, customAnswers: $customAnswers) { answers in
                        submittedAnswers = answers
                        continueAfterConfirmation = true
                    }
                }
                .sheet(isPresented: $showModel) {
                    NavigationStack {
                        CustomModelEntry().toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showModel = false } } }
                    }
                }
                .onDisappear { task?.cancel() }
        }
    }
    @ViewBuilder private var photoPreview: some View {
        if let preview {
            Image(uiImage: preview).resizable().scaledToFit().frame(maxWidth: .infinity).frame(maxHeight: 230)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(alignment: .topTrailing) {
                    Label("照片已就绪", systemImage: "checkmark.circle.fill").font(.caption.weight(.medium))
                        .padding(8).background(.ultraThinMaterial, in: Capsule()).padding(10)
                }
        } else {
            Card {
                VStack(spacing: 14) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 44, weight: .light)).foregroundStyle(skin.accent)
                    Text("把这一餐拍下来").font(.title3.bold())
                    Text("拍全食物、保持光线明亮\n份量不确定，稍后也能修改")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 24)
            }
        }
    }
    private func resultCard(_ result: MealAnalysis) -> some View {
        Card {
            Label(result.confirmationApplied == true ? "已结合你的确认重新估算" : "估算完成，核对后保存", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(skin.accent).accessibilityIdentifier("photo.result")
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(result.items.reduce(0) { $0 + $1.estimatedKcal }.rounded()))")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text("kcal").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("\(result.items.count) 项食物").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(result.items.prefix(5).enumerated()), id: \.offset) { _, item in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).font(.subheadline.weight(.medium))
                        Text("约 \(Int(item.estimatedGrams.rounded())) 克").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(item.estimatedKcal.rounded())) kcal").font(.subheadline).monospacedDigit()
                }
            }
            Text(result.summary).font(.subheadline).foregroundStyle(.secondary)
            if result.portionBasis == "consumed" {
                Label("已按说明折算实际摄入，核对时可保留「全部」。", systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(skin.accent)
            }
            DisclosureGroup("查看估算依据") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(result.assumptions.enumerated()), id: \.offset) { _, value in
                        Label(value, systemImage: "info.circle").font(.caption)
                    }
                }.foregroundStyle(.secondary).padding(.top, 6)
            }.font(.caption)
        }
    }
    private func setImage(_ image: UIImage) async {
        loadingImage = true
        defer { loadingImage = false }
        do {
            let jpeg = try await Task.detached(priority: .userInitiated) {
                let size = image.size
                guard size.width > 0, size.height > 0 else { throw AIError.message("图片尺寸无效。") }
                let scale = min(1, 1600 / max(size.width, size.height))
                let target = CGSize(width: size.width * scale, height: size.height * scale)
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1; format.opaque = true; format.preferredRange = .standard
                let normalized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
                    UIColor.white.setFill(); UIRectFill(CGRect(origin: .zero, size: target))
                    image.draw(in: CGRect(origin: .zero, size: target))
                }
                guard let jpeg = normalized.jpegData(compressionQuality: 0.75), jpeg.count <= 4_000_000 else {
                    throw AIError.message("照片压缩后仍过大，请选择尺寸更小的图片。")
                }
                return jpeg
            }.value
            try Task.checkCancellation()
            imageData = jpeg; preview = UIImage(data: jpeg); analysis = nil; error = nil; cancelled = false
            resetConfirmation()
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func begin() {
        guard store.service.isValid else { error = "请先在“我的 → NAS 账号”登录。"; return }
        analysisID = UUID()
        if !store.snapshot.aiConsent { consent = true } else { run() }
    }
    private func resetConfirmation() {
        pendingQuestions = []
        choices = [:]
        customAnswers = [:]
        submittedAnswers = []
        continueAfterConfirmation = false
    }
    private func resumeAfterConfirmation() {
        guard continueAfterConfirmation else { return }
        continueAfterConfirmation = false
        run(answers: submittedAnswers)
    }
    private func run(answers: [MealClarificationAnswer] = []) {
        guard !running, !loadingImage, let imageData else { return }
        running = true; error = nil; cancelled = false; analysis = nil; started = Date()
        progress = .init(stage: "uploading", message: answers.isEmpty ? "正在发送本次照片与补充说明" : "正在提交你确认的信息")
        history = [progress]
        task = Task { @MainActor in
            defer { running = false }
            do {
                let response = try await AIClient(configuration: store.service).meal(image: imageData, note: note, answers: answers, analysisID: analysisID) { update in
                    progress = update
                    if history.last?.stage != update.stage { history.append(update) }
                }
                try Task.checkCancellation()
                guard !response.items.isEmpty, response.items.count <= 20, response.items.map(\.foodItem).allSatisfy(\.isValid) else {
                    throw AIError.message("识别结果不完整，请重试或手动记录。")
                }
                if answers.isEmpty && !response.pendingQuestions.isEmpty {
                    pendingQuestions = response.pendingQuestions
                    showConfirmation = true
                } else {
                    guard answers.isEmpty || response.confirmationApplied == true else {
                        throw AIError.message("服务器没有确认收到答案，请重试。")
                    }
                    resetConfirmation()
                    analysis = response
                    Task { await membership.refresh() }
                }
            } catch is CancellationError { cancelled = true }
            catch AIError.quotaExhausted(let message) {
                error = message
                await membership.refresh()
                showQuota = true
            }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.cameraCaptureMode = .photo
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
