import SwiftUI

enum MealAnswerChoice: Equatable {
    case option(String)
    case custom
    case unknown
}

struct MealConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    let questions: [MealClarification]
    @Binding var choices: [Int: MealAnswerChoice]
    @Binding var customAnswers: [Int: String]
    let onSubmit: ([MealClarificationAnswer]) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("补充下面的信息，AI 会结合原图重新估算。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ForEach(Array(questions.enumerated()), id: \.offset) { index, item in
                        Card {
                            Text("\(index + 1). \(item.question)").font(.headline)
                            ForEach(Array(item.options.enumerated()), id: \.offset) { position, option in
                                if item.options.firstIndex(of: option) == position, !["不确定", "自行填写"].contains(option) {
                                    choice(option, .option(option), index: index)
                                }
                            }
                            choice("自行填写", .custom, index: index)
                            if choices[index] == .custom {
                                TextField("例如：半根，大约 80 克", text: Binding(
                                    get: { customAnswers[index, default: ""] },
                                    set: { customAnswers[index] = String($0.prefix(200)) }
                                ), axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("confirmation.custom.\(index)")
                            }
                            choice("不确定", .unknown, index: index)
                        }
                    }
                }.padding(18)
            }
            .background(Theme.background)
            .navigationTitle("确认食物信息").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("稍后") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button("确认并继续分析") {
                    onSubmit(answers)
                    dismiss()
                }.buttonStyle(PrimaryButtonStyle()).disabled(!allAnswered)
                    .accessibilityIdentifier("confirmation.continue")
                    .padding(.horizontal, 18).padding(.vertical, 10).background(Theme.background)
            }
        }
    }

    private var allAnswered: Bool {
        questions.indices.allSatisfy { index in
            guard let selection = choices[index] else { return false }
            return selection != .custom || !customText(index).isEmpty
        }
    }

    private func customText(_ index: Int) -> String {
        customAnswers[index, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var answers: [MealClarificationAnswer] {
        questions.enumerated().map { index, item in
            let value: String?
            switch choices[index] {
            case .option(let option): value = option
            case .custom: value = customText(index)
            default: value = nil
            }
            return MealClarificationAnswer(question: item.question, answer: value)
        }
    }

    private func choice(_ title: String, _ value: MealAnswerChoice, index: Int) -> some View {
        let selected = choices[index] == value
        return Button { choices[index] = value } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle").foregroundStyle(Theme.green)
                Text(title).font(.subheadline).foregroundStyle(.primary)
                Spacer(minLength: 0)
            }.padding(11).background(selected ? Theme.softGreen : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier(value == .unknown ? "confirmation.unknown.\(index)" : title)
    }
}
