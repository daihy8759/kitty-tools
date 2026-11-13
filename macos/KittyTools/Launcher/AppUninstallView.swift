// 启动器里的卸载预览：应用本身和可选的关联文件。

import SwiftUI

struct AppUninstallView: View {
  @Bindable var model: LauncherModel
  let state: LauncherModel.UninstallState

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        Text("卸载「\(state.item.title)」").font(.system(size: 14, weight: .semibold))
        Text("应用和勾选的文件会移到废纸篓。运行中的应用会先退出。")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
              Image(systemName: "checkmark.square.fill").foregroundStyle(.secondary)
              fileLabel(URL(filePath: state.item.target), title: state.item.title + "（必选）")
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              state.selection == 0 ? Style.selectedFill : .clear, in: .rect(cornerRadius: 8)
            )
            .id(0)
            .accessibilityElement(children: .combine)
            if state.sharedBundleID {
              Text("另一个应用使用相同的标识符，未列出关联文件。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(8)
            } else if state.files.isEmpty {
              Text("没有找到可列出的关联文件，部分文件可能需要权限。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(8)
            } else {
              Text("关联文件（默认保留）")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 4)
              ForEach(Array(state.files.enumerated()), id: \.element) { index, url in
                Toggle(
                  isOn: Binding(
                    get: { state.checked.contains(url) },
                    set: { _ in model.selectUninstallFile(index) }
                  )
                ) {
                  fileLabel(url, title: url.lastPathComponent)
                }
                .toggleStyle(.checkbox)
                .disabled(state.isRunning)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                  state.selection == index + 1 ? Style.selectedFill : .clear,
                  in: .rect(cornerRadius: 8)
                )
                .id(index + 1)
              }
            }
          }
        }
        .onChange(of: state.selection) { _, selection in
          proxy.scrollTo(selection)
        }
      }
    }
    .padding(16)
  }

  private func fileLabel(_ url: URL, title: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
      Text((url.path as NSString).abbreviatingWithTildeInPath)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .help(url.path)
  }
}
