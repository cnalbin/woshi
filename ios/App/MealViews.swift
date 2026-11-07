import SwiftUI
import PhotosUI
import UIKit

struct MealEditor: View {
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
                        .disabled(items.count >= 30)
                } header: { Text("食物与热量 · 点击修改，左滑删除") }
                Section {
                    Picker("实际吃了", selection: $fraction) {
                        Text("全部").tag(1.0); Text("1/2").tag(0.5); Text("1/4").tag(0.25)
                    }.pickerStyle(.segmented)
                    HStack {
                        Text("本次摄入").font(.headline)
                        Spacer()
                        Text("\(Int(total.rounded())) kcal").font(.title2.bold()).foregroundStyle(Theme.green)
                    }
                } footer: { Text("食物列表显示整份，保存时按所选比例折算。已保存记录再次打开时，列表显示上次实际吃下的量。") }
                if let summary = analysis?.summary ?? existing?.summary, !summary.isEmpty {
                    Section("估算依据") {
                        Label("AI 估算，保存前请核对", systemImage: "sparkles").foregroundStyle(Theme.green)
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
                Section {
                    Button(saving ? "正在保存…" : "确认并保存") { save() }.buttonStyle(PrimaryButtonStyle())
                        .disabled(!valid || saving || store.storageUnavailable)
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                if existing != nil {
                    Section { Button("删除这条记录", role: .destructive) { deleteConfirmation = true } }
                }
            }
            .navigationTitle(existing == nil ? "确认这餐" : "编辑记录").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .onAppear { initialize() }
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

    private var previewImage: UIImage? {
        if let photoData { return UIImage(data: photoData) }
        return existing.flatMap { store.photo(for: $0) }
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
            Form {
                Section {
                    TextField("食物名称", text: $name)
                    HStack { Text("份量（可选）"); TextField("克数", text: $grams).keyboardType(.decimalPad).multilineTextAlignment(.trailing); Text("克").foregroundStyle(.secondary) }
                    HStack { Text("热量"); TextField("必填", text: $kcal).keyboardType(.decimalPad).multilineTextAlignment(.trailing); Text("kcal").foregroundStyle(.secondary) }
                } footer: { Text("可直接输入包装标签或你确认的热量。份量未知时可以留空。") }
                if let base = food.grams, base > 0, let next = NumberText.parse(grams), next > 0 {
                    Section {
                        Button("按新克数同比换算热量") { kcal = (food.kcal * next / base).formatted(.number.grouping(.never).precision(.fractionLength(0...1))) }
                    } footer: { Text("换算假设食物配方和热量密度相同；也可直接修改热量。") }
                }
            }
            .navigationTitle("编辑食物").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { if let updated { onSave(updated); dismiss() } }.disabled(updated == nil) }
            }
            .onAppear {
                name = food.name; grams = food.grams.map { $0.formatted(.number.grouping(.never).precision(.fractionLength(0...1))) } ?? ""
                kcal = food.name.isEmpty ? "" : food.kcal.formatted(.number.grouping(.never).precision(.fractionLength(0...1)))
            }
        }
    }
}

struct PhotoMealView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let initialDate: Date
    @State private var selection: PhotosPickerItem?
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var imageData: Data?
    @State private var note = ""
    @State private var loadingImage = false
    @State private var running = false
    @State private var task: Task<Void, Never>?
    @State private var progress = AnalysisProgress(stage: "uploading", message: "正在上传本次照片")
    @State private var started = Date()
    @State private var analysis: MealAnalysis?
    @State private var error: String?
    @State private var consent = false
    @State private var review = false
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let data = imageData, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity)
                            .frame(maxHeight: 310).clipShape(RoundedRectangle(cornerRadius: 22))
                    } else {
                        VStack(spacing: 15) {
                            Image(systemName: "camera.viewfinder").font(.system(size: 58)).foregroundStyle(Theme.green)
                            Text("把这一餐拍下来").font(.title2.bold())
                            Text("拍全食物，光线明亮；可以补充饭量、做法和实际吃下的比例。")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 42)
                            .padding(.horizontal, 18).background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
                    }
                    HStack(spacing: 14) {
                        Button { showCamera = true } label: { Label("拍摄照片", systemImage: "camera") }
                            .buttonStyle(.borderedProminent).disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                        Button { showLibrary = true } label: { Label("选择照片", systemImage: "photo") }.buttonStyle(.bordered)
                        if loadingImage { ProgressView() }
                    }.disabled(running || loadingImage)
                    Card {
                        Text("补充说明（可选）").font(.headline)
                        TextField("例如：半碗米饭，鸡肉去皮，汤没喝", text: $note, axis: .vertical)
                            .lineLimit(2...4).disabled(running)
                            .onChange(of: note) { _, value in if value.count > 500 { note = String(value.prefix(500)) } }
                        Text("照片与补充说明会发送给已配置的 AI 服务。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if running {
                        AnalysisStatusView(progress: progress, startedAt: started) { task?.cancel() }
                    } else {
                        Button { begin() } label: { Label(analysis == nil ? "开始 AI 分析" : "重新分析", systemImage: "sparkles") }
                            .buttonStyle(PrimaryButtonStyle()).disabled(imageData == nil || loadingImage)
                    }
                    if let error {
                        Card {
                            Label("本次分析未完成", systemImage: "exclamationmark.circle").font(.headline)
                            Text(error).font(.subheadline).foregroundStyle(.secondary)
                            Button("改为手动记录") { analysis = nil; review = true }
                        }
                    }
                    if let analysis, !running {
                        Card {
                            Label("分析完成 · 等待你确认", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(Theme.green)
                            Text(analysis.summary).font(.subheadline)
                            Text("识别到 \(analysis.items.count) 项食物，约 \(Int(analysis.items.reduce(0) { $0 + $1.estimatedKcal }.rounded())) kcal")
                                .font(.subheadline.weight(.semibold))
                            Button("核对食物与份量") { review = true }.buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }.padding(18)
            }.background(Theme.background)
                .navigationTitle("拍照记餐").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
                .photosPicker(isPresented: $showLibrary, selection: $selection, matching: .images)
                .task(id: selection) {
                    guard let selection else { return }
                    loadingImage = true
                    defer { loadingImage = false }
                    do {
                        guard let data = try await selection.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                            throw AIError.message("无法读取这张照片，请换一张。")
                        }
                        try Task.checkCancellation()
                        setImage(image)
                    } catch is CancellationError {} catch { self.error = error.localizedDescription }
                }
                .fullScreenCover(isPresented: $showCamera) { CameraPicker { image in setImage(image) } }
                .sheet(isPresented: $consent) {
                    AIConsentView {
                        do { try store.setAIConsent(true); run() } catch { self.error = error.localizedDescription }
                    }
                }
                .sheet(isPresented: $review, onDismiss: { if saved { dismiss() } }) {
                    MealEditor(initialDate: initialDate, analysis: analysis, photoData: imageData) { saved = true }
                }
                .onDisappear { task?.cancel() }
        }
    }

    private func setImage(_ image: UIImage) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { error = "图片尺寸无效。"; return }
        let scale = min(1, 1600 / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true; format.preferredRange = .standard
        let normalized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            UIColor.white.setFill(); UIRectFill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = normalized.jpegData(compressionQuality: 0.75), jpeg.count <= 4_000_000 else {
            error = "照片压缩后仍过大，请选择尺寸更小的图片。"; return
        }
        imageData = jpeg; analysis = nil; error = nil
    }

    private func begin() {
        guard ServiceConfiguration.current.isValid else { error = "请先在“我的 → AI 服务设置”填写后端地址和访问令牌。"; return }
        if !store.snapshot.aiConsent { consent = true } else { run() }
    }
    private func run() {
        guard !running, let imageData else { return }
        running = true; error = nil; analysis = nil; started = Date()
        progress = .init(stage: "uploading", message: "正在上传本次照片")
        task = Task { @MainActor in
            defer { running = false }
            do {
                let response = try await AIClient(configuration: .current).meal(image: imageData, note: note) { progress = $0 }
                try Task.checkCancellation()
                guard !response.items.isEmpty, response.items.count <= 20, response.items.map(\.foodItem).allSatisfy(\.isValid) else {
                    throw AIError.message("识别结果不完整，请重试或手动记录。")
                }
                analysis = response
            } catch is CancellationError { error = "分析已取消，照片草稿仍保留。" }
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
