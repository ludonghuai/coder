import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/git/git_autofetch.dart';
import '../../ide/ide_menu.dart';
import '../../l10n/l10n.dart';
import '../user_settings.dart';
import 'settings_dropdown.dart';
import 'settings_widgets.dart';

/// Settings → General → Git: fetching the workspace's repositories as the
/// app runs, the fast-forward that follows it, and how often it happens.
/// A choice is written at once; the default is not written.
class GitSettingsGroup extends StatelessWidget {
  const GitSettingsGroup({super.key, this.settings});

  /// settings.json; none under test, where choices are not kept.
  final UserSettings? settings;

  /// The periods the dropdown offers, in minutes.
  static const periods = [1, 2, 3, 5, 10, 15, 30];

  /// The default period in minutes: picked, it is written as no setting.
  static const defaultMinutes = 3;

  void _write(String key, Object? value) {
    final settings = this.settings;
    if (settings == null) return;
    unawaited(
      settings.update(key, value).catchError((Object error) {
        // A settings file that does not parse is left as it is.
        debugPrint('$key not kept: $error');
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = this.settings;
    return ListenableBuilder(
      listenable: settings ?? Listenable.merge(const []),
      builder: (context, _) {
        final l10n = context.l10n;
        final autofetch = ideGitAutofetchEnabled(
          settings?[gitAutofetchSetting],
        );
        final seconds = ideGitAutofetchPeriod(
          settings?[gitAutofetchPeriodSetting],
        );
        return SettingsGroup(
          title: l10n.generalSettingsGit,
          children: [
            SettingsCard(
              children: [
                SettingsSwitchRow(
                  label: l10n.generalSettingsGitAutofetch,
                  description: l10n.generalSettingsGitAutofetchDescription,
                  value: autofetch,
                  onChanged: (on) =>
                      _write(gitAutofetchSetting, on ? null : false),
                ),
                SettingsSwitchRow(
                  label: l10n.generalSettingsGitAutoPull,
                  description: l10n.generalSettingsGitAutoPullDescription,
                  value: ideGitAutoPullEnabled(settings?[gitAutoPullSetting]),
                  // It runs as part of the fetch: off with it, it does
                  // nothing.
                  enabled: autofetch,
                  onChanged: (on) =>
                      _write(gitAutoPullSetting, on ? null : false),
                ),
                SettingsRow(
                  label: l10n.generalSettingsGitAutofetchPeriod,
                  trailing: SettingsDropdown(
                    current: _minutesLabel(l10n, seconds),
                    semanticLabel: l10n.generalSettingsGitAutofetchPeriod,
                    entries: () => [
                      for (final minutes in periods)
                        IdeMenuAction(
                          _minutesLabel(l10n, minutes * 60),
                          checked: minutes * 60 == seconds,
                          onSelected: () => _write(
                            gitAutofetchPeriodSetting,
                            minutes == defaultMinutes ? null : minutes * 60,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// [seconds] as the dropdown shows it: whole minutes, or the fraction a
  /// setting that is not one of the choices asks for.
  static String _minutesLabel(AppLocalizations l10n, int seconds) {
    final minutes = seconds / 60;
    final label = minutes == minutes.roundToDouble()
        ? '${minutes.round()}'
        : _withoutTrailingZeros(minutes.toStringAsFixed(2));
    return l10n.gitPeriodMinutes(label);
  }

  /// `0.75`, `1.5`: [value] without the zeros its decimals do not need.
  static String _withoutTrailingZeros(String value) =>
      value.contains('.') ? value.replaceFirst(RegExp(r'\.?0+$'), '') : value;
}
