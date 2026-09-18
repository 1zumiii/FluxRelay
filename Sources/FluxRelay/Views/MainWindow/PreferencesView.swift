import SwiftUI

struct PreferencesView: View {
  @ObservedObject var model: MainWindowModel
  let section: MainWindowModel.PreferencesSection

  @State private var trackerExpanded = false

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        Group {
          switch section {
          case .general:
            generalSettings
          case .download:
            downloadSettings
          case .bittorrent:
            bittorrentSettings
          case .connection:
            connectionSettings
          }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(.trailing, 10)
        .padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)

      if let feedback = model.settingsFeedback {
        settingsFeedbackView(feedback)
          .padding(.top, 10)
      }

      Divider()

      HStack(spacing: 10) {
        Text(L10n.tr("preferences.storage_notice"))
          .font(.system(size: 12))
          .foregroundStyle(.tertiary)

        Spacer()

        Button(L10n.tr("action.restore")) {
          model.resetSettings()
        }

        .disabled(model.isRestartingEngine)

        Button(L10n.tr("action.save_changes")) {
          model.saveSettings()
        }
        .disabled(model.isRestartingEngine)
        .buttonStyle(.borderedProminent)
        .tint(.teal)
      }
      .padding(.top, 14)
    }
  }

  @ViewBuilder
  private func settingsFeedbackView(_ feedback: SettingsFeedback) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if !feedback.applied.isEmpty {
        Label(
          L10n.format(
            "preferences.applied_notice",
            feedback.applied.joined(separator: L10n.tr("common.list_separator"))
          ),
          systemImage: "checkmark.circle.fill"
        )
        .foregroundStyle(.green)
      }

      if !feedback.restartRequired.isEmpty {
        HStack(alignment: .top, spacing: 10) {
          Label(
            L10n.format(
              "preferences.restart_notice",
              feedback.restartRequired.joined(separator: L10n.tr("common.list_separator"))
            ),
            systemImage: "arrow.clockwise.circle"
          )
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)

          Spacer()

          Button(
            model.isRestartingEngine
              ? L10n.tr("preferences.restart_in_progress")
              : L10n.tr("preferences.restart_action")
          ) {
            model.restartEngine()
          }
          .disabled(model.isRestartingEngine)
          .buttonStyle(.borderedProminent)
          .tint(.orange)
        }
      }

      if feedback.applied.isEmpty && feedback.restartRequired.isEmpty {
        Label(L10n.tr("preferences.no_changes"), systemImage: "minus.circle")
          .foregroundStyle(.secondary)
      }

      if model.restartEngineFailed {
        Label(L10n.tr("preferences.restart_failed"), systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
      }
    }
    .font(.system(size: 12, weight: .medium))
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var generalSettings: some View {
    VStack(alignment: .leading, spacing: 24) {
      PreferenceGroup(title: L10n.tr("preferences.group.application")) {
        preferenceToggle(
          L10n.tr("preferences.open_at_login.title"),
          subtitle: L10n.tr("preferences.open_at_login.subtitle"),
          image: "power",
          color: .blue,
          isOn: $model.settings.openAtLogin
        )
        PreferenceDivider()
        preferenceToggle(
          L10n.tr("preferences.notifications.title"),
          subtitle: L10n.tr("preferences.notifications.subtitle"),
          image: "bell.fill",
          color: .orange,
          isOn: $model.settings.taskNotification
        )
        PreferenceDivider()
        PreferenceRow(
          title: L10n.tr("preferences.language.title"),
          subtitle: L10n.tr("preferences.language.subtitle"),
          image: "globe",
          color: .teal
        ) {
          Picker("", selection: languageBinding) {
            ForEach(L10n.Language.allCases) { language in
              Text(language.title).tag(language.rawValue)
            }
          }
          .labelsHidden()
          .frame(width: 170)
        }
      }

      PreferenceGroup(title: L10n.tr("preferences.group.task_behavior")) {
        preferenceToggle(
          L10n.tr("preferences.default_pause.title"),
          subtitle: L10n.tr("preferences.default_pause.subtitle"),
          image: "pause.circle.fill",
          color: .purple,
          isOn: $model.settings.pause
        )
        PreferenceDivider()
        preferenceToggle(
          L10n.tr("preferences.skip_removal_confirmation.title"),
          subtitle: L10n.tr("preferences.skip_removal_confirmation.subtitle"),
          image: "trash.fill",
          color: .red,
          isOn: $model.settings.noConfirmBeforeDeleteTask
        )
      }
    }
  }

  private var downloadSettings: some View {
    VStack(alignment: .leading, spacing: 24) {
      PreferenceGroup(title: L10n.tr("common.destination")) {
        PreferenceRow(
          title: L10n.tr("preferences.download_folder.title"),
          subtitle: model.settings.downloadDirectory,
          image: "folder.fill",
          color: .blue
        ) {
          Button {
            model.chooseDownloadDirectory()
          } label: {
            Image(systemName: "ellipsis")
          }
          .buttonStyle(.bordered)
          .help(L10n.tr("common.choose_download_folder"))
        }
      }

      PreferenceGroup(title: L10n.tr("preferences.group.speed_limits"), footer: L10n.tr("preferences.speed_limits.footer")) {
        PreferenceRow(title: L10n.tr("transfer.download_speed"), subtitle: L10n.tr("preferences.download_limit.subtitle"), image: "arrow.down", color: .teal) {
          limitField($model.settings.maxOverallDownloadLimit)
        }
        PreferenceDivider()
        PreferenceRow(title: L10n.tr("transfer.upload_speed"), subtitle: L10n.tr("preferences.upload_limit.subtitle"), image: "arrow.up", color: .indigo) {
          limitField($model.settings.maxOverallUploadLimit)
        }
      }

      PreferenceGroup(title: L10n.tr("preferences.group.scheduling")) {
        preferenceToggle(
          L10n.tr("adaptive_split.title"),
          subtitle: L10n.tr("adaptive_split.subtitle"),
          image: "square.grid.3x3.fill",
          color: .purple,
          isOn: $model.settings.adaptiveSplits
        )
        PreferenceDivider()
        preferenceToggle(
          L10n.tr("adaptive_connection.title"),
          subtitle: L10n.tr("adaptive_connection.subtitle"),
          image: "speedometer",
          color: .teal,
          isOn: $model.settings.adaptiveConnections
        )
        PreferenceDivider()
        preferenceToggle(
          L10n.tr("preferences.continue.title"),
          subtitle: L10n.tr("preferences.continue.subtitle"),
          image: "arrow.clockwise",
          color: .green,
          isOn: $model.settings.continueDownloads
        )
        PreferenceDivider()
        preferenceStepper(L10n.tr("preferences.concurrent_downloads.title"), subtitle: L10n.tr("preferences.concurrent_downloads.subtitle"), image: "square.stack.3d.up.fill", color: .blue, value: $model.settings.maxConcurrentDownloads, range: 1...50)
        PreferenceDivider()
        preferenceNumberField(L10n.tr("preferences.connections_per_server.title"), subtitle: model.settings.adaptiveConnections ? L10n.tr("preferences.connections_per_server.adaptive_subtitle") : L10n.tr("preferences.connections_per_server.fixed_subtitle"), image: "server.rack", color: .orange, value: $model.settings.maxConnectionPerServer, range: Aria2Limits.connectionRange)
        PreferenceDivider()
        preferenceNumberField(L10n.tr("preferences.split.title"), subtitle: model.settings.adaptiveSplits ? L10n.tr("preferences.split.adaptive_subtitle") : L10n.tr("preferences.split.fixed_subtitle"), image: "square.grid.3x3.fill", color: .purple, value: $model.settings.split, range: Aria2Limits.connectionRange)
      }
    }
  }

  private var bittorrentSettings: some View {
    VStack(alignment: .leading, spacing: 24) {
      PreferenceGroup(title: L10n.tr("preferences.section.bittorrent")) {
        preferenceToggle(
          L10n.tr("preferences.save_metadata.title"),
          subtitle: L10n.tr("preferences.save_metadata.subtitle"),
          image: "doc.badge.arrow.up.fill",
          color: .blue,
          isOn: $model.settings.btSaveMetadata
        )
        PreferenceDivider()
        preferenceToggle(
          L10n.tr("preferences.force_encryption.title"),
          subtitle: L10n.tr("preferences.force_encryption.subtitle"),
          image: "lock.fill",
          color: .indigo,
          isOn: $model.settings.btForceEncryption
        )
      }

      PreferenceGroup(title: L10n.tr("preferences.group.seeding")) {
        preferenceToggle(
          L10n.tr("preferences.seeding_enabled.title"),
          subtitle: L10n.tr("preferences.seeding_enabled.subtitle"),
          image: "arrow.up.circle.fill",
          color: .indigo,
          isOn: Binding(
            get: { model.settings.seedingEnabled },
            set: { enabled in
              model.settings.seedingEnabled = enabled
              if enabled && model.settings.seedTime == 0 {
                model.settings.seedTime = 60
              }
            }
          )
        )
        PreferenceDivider()
        preferenceStepper(L10n.tr("bittorrent.seed_ratio"), subtitle: L10n.tr("preferences.seed_ratio.subtitle"), image: "arrow.triangle.2.circlepath", color: .green, value: $model.settings.seedRatio, range: 0...100)
          .disabled(!model.settings.seedingEnabled)
          .opacity(model.settings.seedingEnabled ? 1 : 0.45)
        PreferenceDivider()
        preferenceStepper(L10n.tr("preferences.seed_time.title"), subtitle: L10n.tr("preferences.seed_time.subtitle"), image: "clock.fill", color: .orange, value: $model.settings.seedTime, range: 1...10080)
          .disabled(!model.settings.seedingEnabled)
          .opacity(model.settings.seedingEnabled ? 1 : 0.45)
      }

      PreferenceGroup(title: L10n.tr("preferences.group.trackers"), footer: trackerFooter) {
        Button {
          withAnimation(.easeInOut(duration: 0.18)) {
            trackerExpanded.toggle()
          }
        } label: {
          HStack(spacing: 12) {
            PreferenceIcon(image: "antenna.radiowaves.left.and.right", color: .teal)

            VStack(alignment: .leading, spacing: 3) {
              Text(L10n.tr("preferences.trackers.custom_list"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
              Text(trackerSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(trackerExpanded ? L10n.tr("action.collapse") : L10n.tr("action.edit"))
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.tertiary)
              .rotationEffect(.degrees(trackerExpanded ? 90 : 0))
          }
          .padding(14)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if trackerExpanded {
          PreferenceDivider()
          TextEditor(text: $model.settings.btTracker)
            .font(.system(size: 11, design: .monospaced))
            .frame(minHeight: 150)
            .scrollContentBackground(.hidden)
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            }
            .padding(14)
            .padding(.top, -4)
        }
      }
    }
  }

  private var connectionSettings: some View {
    VStack(alignment: .leading, spacing: 24) {
      PreferenceGroup(
        title: L10n.tr("preferences.group.proxy"),
        footer: model.proxyTestMessage ?? L10n.tr("preferences.proxy.footer")
      ) {
        PreferenceRow(
          title: L10n.tr("preferences.proxy.mode.title"),
          subtitle: L10n.tr("preferences.proxy.mode.subtitle"),
          image: "network",
          color: .indigo
        ) {
          Picker("", selection: $model.settings.proxyMode) {
            ForEach(ProxyMode.allCases) { mode in
              Text(mode.title).tag(mode)
            }
          }
          .labelsHidden()
          .frame(width: 150)
        }

        if model.settings.proxyMode == .manual {
          PreferenceDivider()
          PreferenceRow(
            title: L10n.tr("preferences.proxy.scheme.title"),
            subtitle: L10n.tr("preferences.proxy.scheme.subtitle"),
            image: "link",
            color: .purple
          ) {
            Picker("", selection: $model.settings.proxyScheme) {
              ForEach(ProxyScheme.allCases) { scheme in
                Text(scheme.title).tag(scheme)
              }
            }
            .labelsHidden()
            .frame(width: 100)
          }

          PreferenceDivider()
          PreferenceRow(
            title: L10n.tr("preferences.proxy.server.title"),
            subtitle: L10n.tr("preferences.proxy.server.subtitle"),
            image: "server.rack",
            color: .teal
          ) {
            HStack(spacing: 7) {
              TextField(ProxyConfiguration.defaultHost, text: $model.settings.proxyHost)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .frame(width: 150)
              PortField(value: $model.settings.proxyPort, range: 1...65535)
            }
          }
        }

        PreferenceDivider()
        PreferenceRow(
          title: L10n.tr("preferences.proxy.test.title"),
          subtitle: L10n.tr("preferences.proxy.test.subtitle"),
          image: "checkmark.shield.fill",
          color: .green
        ) {
          Button {
            model.testProxy()
          } label: {
            if model.isTestingProxy {
              ProgressView()
                .controlSize(.small)
                .frame(width: 52)
            } else {
              Text(L10n.tr("preferences.proxy.test.action"))
            }
          }
          .disabled(
            model.isTestingProxy
              || (model.settings.proxyMode == .manual
                && model.settings.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          )
        }
      }

      PreferenceGroup(title: L10n.tr("preferences.section.rpc"), footer: L10n.tr("preferences.rpc.footer")) {
        PreferenceRow(title: L10n.tr("preferences.rpc_port.title"), subtitle: L10n.tr("preferences.rpc_port.subtitle"), image: "dot.radiowaves.left.and.right", color: .blue) {
          PortField(value: $model.settings.rpcPort)
        }
        PreferenceDivider()
        PreferenceRow(title: L10n.tr("preferences.rpc_secret.title"), subtitle: L10n.tr("preferences.rpc_secret.subtitle"), image: "key.fill", color: .orange) {
          RPCSecretField(text: $model.settings.rpcSecret)
        }
      }

      PreferenceGroup(title: L10n.tr("preferences.group.incoming_connections")) {
        PreferenceRow(title: L10n.tr("preferences.bt_port.title"), subtitle: L10n.tr("preferences.bt_port.subtitle"), image: "arrow.left.arrow.right.circle.fill", color: .purple) {
          PortField(value: $model.settings.listenPort)
        }
        PreferenceDivider()
        PreferenceRow(title: L10n.tr("preferences.dht_port.title"), subtitle: L10n.tr("preferences.dht_port.subtitle"), image: "network", color: .teal) {
          PortField(value: $model.settings.dhtListenPort)
        }
      }

      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "info.circle.fill")
          .foregroundStyle(.blue)
        Text(L10n.tr("preferences.connection.info"))
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(14)
      .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private var trackerCount: Int {
    TrackerList.supportedEntries(from: model.settings.btTracker).count
  }

  private var languageBinding: Binding<String> {
    Binding(
      get: { model.settings.appLanguage },
      set: { language in
        L10n.configure(language: language)
        model.settings.appLanguage = language
      }
    )
  }

  private var unsupportedTrackerCount: Int {
    TrackerList.unsupportedEntries(from: model.settings.btTracker).count
  }

  private var trackerSummary: String {
    if trackerCount == 0, unsupportedTrackerCount == 0 { return L10n.tr("preferences.trackers.none") }
    if unsupportedTrackerCount > 0 {
      return L10n.format("preferences.trackers.summary_with_ignored", String(trackerCount), String(unsupportedTrackerCount))
    }
    return L10n.format("preferences.trackers.summary", String(trackerCount))
  }

  private var trackerFooter: String {
    if unsupportedTrackerCount > 0 {
      return L10n.format("preferences.trackers.ignored_footer", String(unsupportedTrackerCount))
    }
    return L10n.tr("preferences.trackers.help")
  }

  private func preferenceToggle(
    _ title: String,
    subtitle: String,
    image: String,
    color: Color,
    isOn: Binding<Bool>
  ) -> some View {
    PreferenceRow(title: title, subtitle: subtitle, image: image, color: color) {
      Toggle("", isOn: isOn)
        .labelsHidden()
        .toggleStyle(.switch)
    }
  }

  private func preferenceStepper(
    _ title: String,
    subtitle: String,
    image: String,
    color: Color,
    value: Binding<Int>,
    range: ClosedRange<Int>
  ) -> some View {
    PreferenceRow(title: title, subtitle: subtitle, image: image, color: color) {
      Stepper(value: value, in: range) {
        Text("\(value.wrappedValue)")
          .font(.system(size: 13, weight: .medium, design: .rounded))
          .monospacedDigit()
          .frame(width: 54, alignment: .trailing)
      }
      .fixedSize()
    }
  }

  private func preferenceNumberField(
    _ title: String,
    subtitle: String,
    image: String,
    color: Color,
    value: Binding<Int>,
    range: ClosedRange<Int>
  ) -> some View {
    PreferenceRow(title: title, subtitle: subtitle, image: image, color: color) {
      IntegerStepperField(value: value, range: range)
    }
  }

  private func limitField(_ value: Binding<String>) -> some View {
    HStack(spacing: 6) {
      TextField("0", text: value)
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .frame(width: 92)
      Text("/s")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
  }
}
