import SwiftUI

struct PreferenceGroup<Content: View>: View {
  let title: String
  let footer: String?
  let content: Content

  init(title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.footer = footer
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(title)
        .font(.system(size: 14, weight: .semibold))
        .padding(.leading, 3)

      VStack(spacing: 0) {
        content
      }
      .background {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color(nsColor: .controlBackgroundColor).opacity(0.78))
      }
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(Color.primary.opacity(0.055), lineWidth: 1)
      }

      if let footer {
        Text(footer)
          .font(.system(size: 11))
          .foregroundStyle(.tertiary)
          .padding(.horizontal, 4)
      }
    }
  }
}

struct PreferenceRow<Trailing: View>: View {
  let title: String
  let subtitle: String
  let image: String
  let color: Color
  let trailing: Trailing

  init(
    title: String,
    subtitle: String,
    image: String,
    color: Color,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.subtitle = subtitle
    self.image = image
    self.color = color
    self.trailing = trailing()
  }

  var body: some View {
    HStack(spacing: 12) {
      PreferenceIcon(image: image, color: color)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.primary)
        Text(subtitle)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer(minLength: 18)
      trailing
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
  }
}

struct PreferenceIcon: View {
  let image: String
  let color: Color

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(color.gradient)
      Image(systemName: image)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
    }
    .frame(width: 28, height: 28)
  }
}

struct PreferenceDivider: View {
  var body: some View {
    Divider()
      .padding(.leading, 54)
  }
}

struct PortField: View {
  @Binding var value: Int
  let range: ClosedRange<Int>
  @State private var text: String
  @FocusState private var isFocused: Bool

  init(value: Binding<Int>, range: ClosedRange<Int> = 1024...65535) {
    self._value = value
    self.range = range
    self._text = State(initialValue: String(value.wrappedValue))
  }

  var body: some View {
    TextField("\(range.lowerBound)-\(range.upperBound)", text: $text)
      .textFieldStyle(.roundedBorder)
      .font(.system(size: 13, design: .monospaced))
      .multilineTextAlignment(.trailing)
      .frame(width: 118)
      .focused($isFocused)
      .onChange(of: text) { _, newValue in
        let digits = newValue.filter(\.isNumber)
        if digits != newValue {
          text = digits
          return
        }

        if let port = Int(digits), range.contains(port) {
          value = port
        }
      }
      .onChange(of: value) { _, newValue in
        if !isFocused {
          text = String(newValue)
        }
      }
      .onChange(of: isFocused) { _, focused in
        if !focused {
          commit()
        }
      }
      .onSubmit(commit)
  }

  private func commit() {
    guard let entered = Int(text) else {
      text = String(value)
      return
    }

    value = min(range.upperBound, max(range.lowerBound, entered))
    text = String(value)
  }
}

struct IntegerStepperField: View {
  @Binding var value: Int
  let range: ClosedRange<Int>

  @State private var text: String
  @FocusState private var isFocused: Bool

  init(value: Binding<Int>, range: ClosedRange<Int>) {
    self._value = value
    self.range = range
    self._text = State(initialValue: String(value.wrappedValue))
  }

  var body: some View {
    HStack(spacing: 6) {
      TextField("\(range.lowerBound)-\(range.upperBound)", text: $text)
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 13, design: .monospaced))
        .multilineTextAlignment(.trailing)
        .frame(width: 72)
        .focused($isFocused)
        .onChange(of: text) { _, newValue in
          let digits = newValue.filter(\.isNumber)
          if digits != newValue {
            text = digits
            return
          }

          if let entered = Int(digits), range.contains(entered) {
            value = entered
          }
        }
        .onChange(of: isFocused) { _, focused in
          if !focused {
            commit()
          }
        }
        .onSubmit(commit)

      Stepper("", value: $value, in: range)
        .labelsHidden()
        .fixedSize()
        .onChange(of: value) { _, newValue in
          text = String(newValue)
        }
    }
  }

  private func commit() {
    guard let entered = Int(text) else {
      text = String(value)
      return
    }

    value = min(range.upperBound, max(range.lowerBound, entered))
    text = String(value)
  }
}

struct RPCSecretField: View {
  @Binding var text: String
  @State private var isRevealed = false

  var body: some View {
    HStack(spacing: 0) {
      Group {
        if isRevealed {
          TextField(L10n.tr("common.not_set"), text: $text)
        } else {
          SecureField(L10n.tr("common.not_set"), text: $text)
        }
      }
      .textFieldStyle(.plain)
      .font(.system(size: 13, design: .monospaced))
      .padding(.horizontal, 9)

      Divider()
        .frame(height: 20)

      secretButton(
        isRevealed ? "eye.slash" : "eye",
        help: isRevealed ? L10n.tr("preferences.rpc_secret.hide") : L10n.tr("preferences.rpc_secret.show")
      ) {
        isRevealed.toggle()
      }

      Divider()
        .frame(height: 20)

      secretButton("dice.fill", help: L10n.tr("preferences.rpc_secret.generate")) {
        text = Self.randomSecret()
      }
    }
    .frame(width: 278, height: 30)
    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .stroke(Color.primary.opacity(0.14), lineWidth: 1)
    }
  }

  private func secretButton(_ image: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: image)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 34, height: 28)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
  }

  private static func randomSecret() -> String {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
    var generator = SystemRandomNumberGenerator()
    return String((0..<32).compactMap { _ in alphabet.randomElement(using: &generator) })
  }
}
