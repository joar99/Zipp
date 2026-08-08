import SwiftUI

public extension View {
    func applyModal(
        presentedModal: Binding<PresentedModal?>,
        presentedModalDetent: Binding<PresentationDetent>
    ) -> some View {
        let sheet = Binding<PresentedModal?>(
            get: { presentedModal.wrappedValue?.isFullScreen == false ? presentedModal.wrappedValue : nil },
            set: { newValue in
                presentedModal.wrappedValue = newValue
            }
        )

        let fullScreen = Binding<PresentedModal?>(
            get: { presentedModal.wrappedValue?.isFullScreen == true ? presentedModal.wrappedValue : nil },
            set: { newValue in
                presentedModal.wrappedValue = newValue
            }
        )

        return self
            .sheet(item: sheet) { item in
                NavigationStack {
                    item.view
                }
                .applyingSheetConfiguration(item.sheetConfiguration, detent: presentedModalDetent)
            }
            .fullScreenCover(item: fullScreen) { item in
                NavigationStack {
                    item.view
                }
            }
    }
}

private extension View {
    @ViewBuilder
    func applyingSheetConfiguration(_ configuration: SheetConfiguration?, detent: Binding<PresentationDetent>) -> some View {
        if let configuration {
            self
                .presentationDetents(configuration.detents, selection: detent)
                .presentationBackgroundInteraction(configuration.backgroundInteractionEnabled ? .enabled : .automatic)
                .interactiveDismissDisabled(!configuration.isDismissable)
        } else {
            self
        }
    }
}

public extension View {
    func applyAlert(presentedAlert: Binding<PresentedAlert?>) -> some View {
        self.alert(item: presentedAlert) { $0.alert }
    }
}

public extension View {
    func disablesInteractivePopGesture(_ disabled: Bool) -> some View {
        background(InteractivePopGestureDisabler(isDisabled: disabled))
    }
}

private struct InteractivePopGestureDisabler: UIViewControllerRepresentable {
    let isDisabled: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            uiViewController.navigationController?.interactivePopGestureRecognizer?.isEnabled = !isDisabled
        }
    }
}
