import 'dart:async';

import 'package:flutter/material.dart';

import '../../chat/chat_session.dart' show KernelChoice;
import '../../ide/ide_button.dart';
import '../../ide/ide_input.dart';
import '../../kernel/thincoder/thincoder_config_file.dart';
import '../../kernel/thincoder/thincoder_config_store.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'settings_widgets.dart';

/// A live thincoder session as Settings → Models (thincoder) reads it
/// (§27.5 ②③): the model choice its kernel projects
/// (`thincoder_choices.dart:46-53`), the session itself to hear a change
/// from, and how to start it again — `ThincoderKernel.restart()`, the chat's
/// own restart (`chat_session.dart:398`).
class ThincoderModelSession {
  const ThincoderModelSession({
    required this.models,
    required this.restart,
    this.listenable,
  });

  /// What the agent reports it offers and has in effect; null while it
  /// reports no model (§27.5 ③).
  final KernelChoice? models;

  /// Starts it again: the new session reads the config file (§27.6).
  final VoidCallback restart;

  /// Where a change of [models] is heard (the session is a [ChangeNotifier]).
  final Listenable? listenable;
}

/// Settings → Models (thincoder): the providers of the config file the
/// thincoder CLI reads, and the model a new session starts with (F24).
///
/// The page writes exactly two things — `providers[]` and the top-level
/// `defaultModel` (D114) — through [ThincoderConfigStore]; everything else
/// in the file stays as the user keeps it. A save is followed by a word and
/// a button, never a restart by itself (§27.6): a turn under way would be
/// cut short.
class ThincoderModelsSettingsPage extends StatefulWidget {
  const ThincoderModelsSettingsPage({
    super.key,
    this.store,
    this.environment,
    this.probe,
  });

  /// Where the page reads and writes; null: the CLI's own `config.json`,
  /// at the folder [environment] names.
  final ThincoderConfigStore? store;

  /// The environment the CLI runs in, for where its file is; the kernel's
  /// own when null (`thincoderEnvironment`).
  final Future<Map<String, String>> Function()? environment;

  /// The live thincoder session, if one is open (U15); null when there is
  /// none, which the page says (§27.5 ②③).
  final ThincoderModelSession? Function()? probe;

  @override
  State<ThincoderModelsSettingsPage> createState() =>
      _ThincoderModelsSettingsPageState();
}

class _ThincoderModelsSettingsPageState
    extends State<ThincoderModelsSettingsPage> {
  /// The CLI's own two reasons a new session has no model (§27.5 ④).
  static const _noProvider = 'No provider is configured.';
  static const _noDefaultModel = 'defaultModel is not set.';
  ThincoderConfigStore? _store;
  ThincoderConfigDocument? _document;

  /// The file could not be read: what to say (§27.5 ⑦).
  ThincoderConfigFailure? _readFailure;
  String? _readDetail;

  /// The form shows: the provider being edited, null for a new one.
  bool _formShown = false;
  String? _editing;

  final _name = TextEditingController();
  final _baseURL = TextEditingController();
  final _apiKey = TextEditingController();
  final _model = TextEditingController();

  bool _saving = false;

  /// Why the last save did not go through (§27.5 ⑦); null once one does.
  ThincoderSaveFailed? _saveFailure;

  /// A save went through in this page: the word and the button under it.
  bool _saved = false;

  /// The file's `providers` was not a list, and one now holds the entry
  /// (§27.4).
  bool _providersReplaced = false;

  @override
  void initState() {
    super.initState();
    // The name says which entry a save meets (§27.4): said as it is typed.
    _name.addListener(_nameChanged);
    unawaited(_findFile());
  }

  void _nameChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _name.removeListener(_nameChanged);
    _name.dispose();
    _baseURL.dispose();
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  /// The file the CLI reads, from the environment it will run in (§27.2).
  Future<void> _findFile() async {
    final given = widget.store;
    if (given != null) {
      _store = given;
      return _read();
    }
    final environment = widget.environment ?? thincoderEnvironment;
    final resolved = thincoderConfigFile(await environment());
    if (!mounted) return;
    setState(() => _store = ThincoderConfigStore(file: resolved));
    await _read();
  }

  Future<void> _read() async {
    final store = _store;
    if (store == null) return;
    try {
      final document = await store.read();
      if (!mounted) return;
      setState(() {
        _document = document;
        _readFailure = null;
        _readDetail = null;
      });
    } on ThincoderConfigException catch (error) {
      if (!mounted) return;
      setState(() {
        _document = null;
        _readFailure = error.reason;
        _readDetail = error.detail;
      });
    }
  }

  void _startAdd() {
    setState(() {
      _formShown = true;
      _editing = null;
      _name.clear();
      _baseURL.clear();
      _apiKey.clear();
      _model.clear();
      _saveFailure = null;
    });
  }

  void _startEdit(ThincoderProvider provider) {
    final ref = _document?.defaultModelRef;
    setState(() {
      _formShown = true;
      _editing = provider.name;
      _name.text = provider.name;
      _baseURL.text = provider.baseURL;
      // Blank keeps the key the file has: one is never shown back (D115).
      _apiKey.clear();
      _model.text = ref?.provider == provider.name ? ref!.model : '';
      _saveFailure = null;
    });
  }

  Future<void> _save() async {
    final store = _store;
    if (store == null || _saving) return;
    setState(() {
      _saving = true;
      _saveFailure = null;
    });
    final result = await store.saveProvider(
      name: _name.text,
      baseURL: _baseURL.text,
      apiKey: _apiKey.text,
      model: _model.text,
    );
    if (!mounted) return;
    switch (result) {
      case ThincoderSaved(:final document, :final providersWasNotList):
        setState(() {
          _saving = false;
          _document = document;
          _readFailure = null;
          _formShown = false;
          _editing = null;
          // The key is not kept around once written (T127).
          _apiKey.clear();
          _saved = true;
          _providersReplaced = providersWasNotList;
        });
      case ThincoderSaveFailed():
        setState(() {
          _saving = false;
          _saveFailure = result;
          _saved = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    // The live session, as it changes: a model picked in the chat's pill
    // shows here too.
    final listenable = widget.probe?.call()?.listenable;
    if (listenable == null) return _page(context);
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) => _page(context),
    );
  }

  Widget _page(BuildContext context) {
    final document = _document;
    final session = widget.probe?.call();
    return SettingsPage(
      title: 'Models (thincoder)',
      description:
          'The providers the thincoder CLI reads, and the model a '
          'new session starts with.',
      children: [
        _location(context),
        _current(context, session, document),
        if (session != null) _candidates(context, session),
        if (document != null && document.missing != null)
          _nothingYet(context, document),
        if (document != null && document.providers.isNotEmpty)
          _providers(context, document),
        if (document != null && !(_formShown && _editing == null))
          _addRow(context),
        if (document != null && _formShown) _form(context),
        if (_saved) _savedLine(context, session),
      ],
    );
  }

  /// ① Where the file is, and whether it is there.
  Widget _location(BuildContext context) => SettingsGroup(
    title: 'Configuration',
    children: [
      SettingsRow(
        label: 'Config file',
        description:
            'What thincoder reads its providers and default model '
            'from. Only those two are written here.',
        below: [
          SelectableText(
            _store?.file.path ?? 'Looking for the environment…',
            style: SettingsText.path,
          ),
          if (_readFailure case final failure?) ...[
            const SizedBox(height: 6),
            _failure(failure, _readDetail, _store?.file.path ?? ''),
          ],
        ],
        trailing: Text(switch (_document?.exists) {
          true => 'Exists',
          false => 'New file',
          null => '',
        }, style: SettingsText.description),
      ),
    ],
  );

  /// ② What the live session reports its model to be.
  Widget _current(
    BuildContext context,
    ThincoderModelSession? session,
    ThincoderConfigDocument? document,
  ) {
    final current = session?.models?.selected;
    final text = current != null
        ? current.id
        : session == null
        ? 'Open a thincoder session and the model its CLI reports shows here.'
        : switch (document?.missing) {
            ThincoderModelMissing.noProvider => _noProvider,
            ThincoderModelMissing.noDefaultModel => _noDefaultModel,
            null => 'The session reports no model yet.',
          };
    return SettingsCard(
      children: [
        SettingsRow(
          label: 'Current model',
          description: 'What the live thincoder session reports.',
          below: [SelectableText(text, style: SettingsText.path)],
        ),
      ],
    );
  }

  /// ③ What the CLI says it offers; the refresh is a new session (§27.6).
  Widget _candidates(BuildContext context, ThincoderModelSession session) {
    final models = session.models;
    final options = models?.options ?? const [];
    final current = models?.selected;
    return SettingsGroup(
      title: 'Models thincoder reports',
      description:
          'What the CLI fetched from its providers. Another one is '
          'picked in the chat’s model menu.',
      children: [
        if (options.length <= 1)
          SettingsRow(
            label: current?.id ?? 'None yet',
            description:
                'One model, or none, so far. Refresh the session to '
                'ask the CLI again.',
            trailing: IdeButton(label: 'Refresh', onPressed: session.restart),
          )
        else
          for (final option in options)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    option.id == current?.id ? Codicons.check : Codicons.blank,
                    size: 14,
                    color: SettingsColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      option.label == option.id
                          ? option.id
                          : '${option.label} · ${option.id}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SettingsText.label,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  /// ④ What to do while a new session would have no model, and why.
  Widget _nothingYet(BuildContext context, ThincoderConfigDocument document) =>
      SettingsGroup(
        title: 'No model yet',
        children: [
          SettingsRow(
            label: document.missing == ThincoderModelMissing.noDefaultModel
                ? _noDefaultModel
                : _noProvider,
            description:
                'Add a provider below. Or set one up in your own '
                'terminal, come back, and refresh the session.',
          ),
        ],
      );

  /// ⑤ The providers the CLI reads, one row each; one action, Edit.
  Widget _providers(BuildContext context, ThincoderConfigDocument document) =>
      SettingsGroup(
        title: 'Providers',
        children: [
          for (final provider in document.providers)
            _providerRow(context, document, provider),
        ],
      );

  /// Where a provider is added — there whether or not any is listed: on an
  /// empty config it is the only way in (§27.5 ④⑥).
  Widget _addRow(BuildContext context) => SettingsCard(
    children: [
      SettingsRow(
        label: 'Add a provider',
        description:
            'One entry in providers[], and the model a new session '
            'starts with.',
        trailing: IdeButton(
          label: 'Add provider',
          icon: Codicons.add,
          onPressed: _startAdd,
        ),
      ),
    ],
  );

  Widget _providerRow(
    BuildContext context,
    ThincoderConfigDocument document,
    ThincoderProvider provider,
  ) {
    final ref = document.defaultModelRef;
    final details = [
      provider.baseURL,
      if (provider.maskedKey.isNotEmpty) provider.maskedKey,
      if (ref?.provider == provider.name) ref!.model,
    ].where((part) => part.isNotEmpty).join(' · ');
    return SettingsRow(
      label: provider.name,
      description: details,
      trailing: IdeButton(
        label: 'Edit',
        secondary: true,
        onPressed: () => _startEdit(provider),
      ),
    );
  }

  /// What a save meets on this name, where the fields do not say it: the
  /// update branch, or a name that adds a second entry (§27.4 —
  /// `config-io.mjs:247` finds an entry by its name).
  ({String label, String description})? get _nameNote {
    final typed = _name.text.trim();
    final editing = _editing;
    if (typed.isEmpty) return null;
    if (typed != editing) {
      for (final provider
          in _document?.providers ?? const <ThincoderProvider>[]) {
        if (provider.name == typed) {
          return (
            label: 'The provider “$typed” is already there',
            description:
                'Saving updates it — its Base URL and key — and '
                'starts new sessions with the model below.',
          );
        }
      }
    }
    if (editing != null && typed != editing) {
      return (
        label: 'Saving under another name adds a provider',
        description: 'The entry “$editing” stays as it is.',
      );
    }
    return null;
  }

  /// ⑥ The four fields, and Save.
  Widget _form(BuildContext context) {
    final editing = _editing;
    return SettingsGroup(
      title: editing == null ? 'New provider' : 'Edit $editing',
      children: [
        _input(
          label: 'Name',
          controller: _name,
          placeholder: 'openai',
          description: 'How defaultModel names it — no “:”.',
        ),
        _input(
          label: 'Base URL',
          controller: _baseURL,
          placeholder: 'https://api.example.com/v1',
          description: 'A trailing slash is dropped.',
        ),
        _input(
          label: 'API key',
          controller: _apiKey,
          obscure: true,
          placeholder: editing == null
              ? 'sk-…'
              : 'Leave blank to keep the key saved',
          description: 'Kept in the config file, as thincoder keeps it.',
        ),
        _input(
          label: 'Model',
          controller: _model,
          placeholder: 'gpt-5',
          description: 'The model a new session starts with (defaultModel).',
        ),
        if (_nameNote case final note?)
          SettingsRow(label: note.label, description: note.description),
        SettingsRow(
          label: 'Save',
          description:
              'Writes providers[] and defaultModel; nothing else in '
              'the file changes.',
          below: [
            if (_saveFailure case final failure?)
              _failure(failure.reason, failure.detail, failure.file.path),
          ],
          trailing: IdeButton(
            label: _saving ? 'Saving…' : 'Save',
            onPressed: _saving ? null : _save,
          ),
        ),
      ],
    );
  }

  Widget _input({
    required String label,
    required TextEditingController controller,
    required String placeholder,
    required String description,
    bool obscure = false,
  }) => SettingsRow(
    label: label,
    description: description,
    trailing: SizedBox(
      width: 300,
      child: IdeInputBox(
        controller: controller,
        placeholder: placeholder,
        semanticsLabel: label,
        obscureText: obscure,
        onSubmitted: (_) => unawaited(_save()),
      ),
    ),
  );

  /// What a save asks of the session (§27.6): a word, and a button — never
  /// a restart by itself.
  Widget _savedLine(BuildContext context, ThincoderModelSession? session) {
    const replaced =
        'The file’s providers was not a list; it is one now, holding '
        'this entry.';
    return SettingsCard(
      children: [
        SettingsRow(
          label:
              'Saved. The model choices update once the session is '
              'reopened.',
          description: _providersReplaced ? replaced : null,
          trailing: IdeButton(
            label: 'Reopen thincoder session',
            // Nothing open, nothing to reopen: a new one reads the file
            // anyway.
            onPressed: session?.restart,
          ),
        ),
      ],
    );
  }

  /// ⑦ A failure as a sentence, and the file it is about.
  Widget _failure(ThincoderConfigFailure reason, String? detail, String path) {
    final text = switch (reason) {
      ThincoderConfigFailure.invalidJson =>
        'The config file is not valid JSON, so nothing was written: $path',
      ThincoderConfigFailure.invalidField =>
        'Not saved: ${detail ?? 'a field is not valid'}. Nothing was '
            'written: $path',
      ThincoderConfigFailure.conflict =>
        'The config file changed while saving, so nothing was written'
            '${detail == null ? '' : ' ($detail)'}. Try again: $path',
      ThincoderConfigFailure.ioError =>
        'The config file could not be written'
            '${detail == null ? '' : ': $detail'}: $path',
      ThincoderConfigFailure.verifyFailed =>
        'The config file was written, but reads back differently'
            '${detail == null ? '' : ' — $detail'}: $path',
    };
    return SelectableText(
      text,
      style: SettingsText.description.copyWith(
        color: themeColors['errorForeground'],
      ),
    );
  }
}
