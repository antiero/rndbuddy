import SwiftUI

struct EditControlOverlay: View {
    @Bindable var model: AppModel
    let editor: StageEditor
    let control: ControlSpec
    let placement: Placement
    let cell: CGSize
    @GestureState private var translation = CGSize.zero
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 16)
                .fill(.black.opacity(0.15))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(editor.selection == control.id ? Design.accent : .white.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [4, 4])))
                .contentShape(.rect)
                .onTapGesture { editor.selection = control.id }
                .gesture(DragGesture().updating($translation) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        var copy = placement
                        copy.column += Int((value.translation.width / cell.width).rounded())
                        copy.row += Int((value.translation.height / cell.height).rounded())
                        editor.place(model, copy)
                    })
            if editor.selection == control.id { Image(systemName: "arrow.up.left.and.arrow.down.right")
                .padding(12).frame(minWidth: 44, minHeight: 44)
                .background(.regularMaterial, in: .circle)
                .gesture(DragGesture().onEnded { value in
                    var copy = placement
                    copy.width += Int((value.translation.width / cell.width).rounded())
                    copy.height += Int((value.translation.height / cell.height).rounded())
                    editor.place(model, copy)
                })
                .accessibilityLabel("Resize \(control.title)")
                .accessibilityHint("Use position and size in the inspector")
            }
        }
        .offset(translation)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Edit \(control.title)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { editor.selection = control.id }
    }
}
