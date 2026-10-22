import 'dart:convert';
import 'dart:io';

import 'package:baocode/chat/chat_session.dart' show KernelChoice;
import 'package:baocode/ide/ide_button.dart';
import 'package:baocode/kernel/kernel_types.dart' show KernelOption;
import 'package:baocode/kernel/thincoder/thincoder_config_store.dart';
import 'package:baocode/platform/event_log.dart';
import 'package:baocode/settings/pages/thincoder_models_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Settings → Models (thincoder) (§27.5): the empty state, the errors, and
/// the key never shown but its last four (T127).
void main() {
  late Directory root;
  late File file;
  late ThincoderConfigStore store;
  var restarts = 0;

  setUp(() {
    root = Directory.systemTemp.createTempSync('thincoder-page');
    file = File(p.join(root.path, 'config.json'));
    store = ThincoderConfigStore(file: file);
    restarts = 0;
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// The button whose label is [label].
  Finder button(String label) => find.byWidgetPredicate(
    (widget) => widget is IdeButton && widget.label == label,
  );

  /// The text field labelled [label].
  Finder field(String label) => find.descendant(
    of: find.bySemanticsLabel(label),
    matching: find.byType(EditableText),
  );

  /// A live thincoder session over scripted model choices.
  ThincoderModelSession? Function() session({
    String? current,
    List<String> options = const [],
  }) {
    final choices = [
      for (final id in options) KernelOption(id, id, Icons.bolt_rounded, ''),
    ];
    return () => ThincoderModelSession(
      models: choices.isEmpty
          ? null
          : KernelChoice(
              options: choices,
              selected: choices.firstWhere(
                (choice) => choice.id == current,
                orElse: () => choices.first,
              ),
              onSelected: (_) {},
            ),
      restart: () => restarts++,
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    ThincoderModelSession? Function()? probe,
  }) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThincoderModelsSettingsPage(store: store, probe: probe),
        ),
      ),
    );
    // The file is read once the page is made.
    await tester.pump();
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String label, String text) async {
    await tester.enterText(field(label).first, text);
    await tester.pump();
  }

  /// Every string the page shows.
  List<String> shown(WidgetTester tester) => [
    for (final text in tester.widgetList<Text>(find.byType(Text))) ?text.data,
    for (final text in tester.widgetList<SelectableText>(
      find.byType(SelectableText),
    ))
      text.data,
  ].whereType<String>().toList();

  testWidgets('a missing file is named where it will be made, with what a '
      'new session would miss', (tester) async {
    await pump(tester);

    expect(shown(tester), contains(file.path));
    expect(find.text('New file'), findsOneWidget);
    expect(find.text('No provider is configured.'), findsOneWidget);
    expect(find.textContaining('Add a provider below'), findsOneWidget);
    // No session open: said, and no candidates to show.
    expect(find.textContaining('Open a thincoder session'), findsOneWidget);
    expect(button('Refresh'), findsNothing);
    // Nothing was made by reading.
    expect(file.existsSync(), isFalse);
  });

  testWidgets('providers with no defaultModel is said as such', (tester) async {
    file.writeAsStringSync(
      '${jsonEncode({
        'providers': [
          {'name': 'openai', 'baseURL': 'https://api.example.com', 'apiKey': 'k'},
        ],
      })}\n',
    );
    await pump(tester);

    expect(find.text('defaultModel is not set.'), findsOneWidget);
    expect(find.text('openai'), findsOneWidget);
    // Editing is the only row action: no Set as default, no removal.
    expect(button('Edit'), findsOneWidget);
    expect(find.textContaining('Set as default'), findsNothing);
    expect(find.textContaining('Delete'), findsNothing);
  });

  testWidgets('T127: a provider saved shows the key’s last four only, the key '
      'field is cleared, and nothing reopens by itself', (tester) async {
    const key = 'sk-test-1234';
    final logs = Directory(p.join(root.path, 'logs'))..createSync();
    EventLog.current = EventLog(logs.path);
    addTearDown(() => EventLog.current = null);
    // A line of the app's own, so the file exists to be read.
    appEvent('test', 'starting');

    await pump(tester, probe: session(current: 'openai:gpt-5'));
    await tester.tap(button('Add provider'));
    await tester.pump();
    await type(tester, 'Name', 'openai');
    await type(tester, 'Base URL', 'https://api.example.com/v1');
    await type(tester, 'API key', key);
    await type(tester, 'Model', 'gpt-5');
    await tester.tap(button('Save'));
    await tester.pump();
    await tester.pump();

    // Written, as asked: entry and defaultModel.
    final raw = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect(raw['defaultModel'], 'openai:gpt-5');
    expect((raw['providers'] as List).single, {
      'name': 'openai',
      'baseURL': 'https://api.example.com/v1',
      'apiKey': key,
    });

    // The row says the last four, never the key.
    expect(find.textContaining('••••1234'), findsOneWidget);
    final texts = shown(tester);
    expect(texts.where((text) => text.contains(key)), isEmpty);
    // The form went, its fields with it — nothing holds the key.
    expect(field('API key'), findsNothing);
    // Reopening is the user's move, not the save's.
    expect(restarts, 0);
    expect(
      find.textContaining('Saved. The model choices update'),
      findsOneWidget,
    );
    await tester.tap(button('Reopen thincoder session'));
    expect(restarts, 1);

    // And the log of the app has no key in it either.
    final log = File(p.join(logs.path, 'events.log'));
    expect(log.existsSync(), isTrue);
    expect(log.readAsStringSync(), isNot(contains(key)));
    // Nor does the full text of the key ever land on screen.
    expect(texts.join('\n'), isNot(contains(key.substring(0, 8))));
    expect(texts.join('\n'), contains('••••'));
  });

  testWidgets('a config that is not JSON is said with its path, and nothing '
      'is offered to save over it', (tester) async {
    const broken = '{not json';
    file.writeAsStringSync(broken);
    await pump(tester);

    expect(
      find.textContaining('The config file is not valid JSON'),
      findsOneWidget,
    );
    expect(shown(tester), contains(contains(file.path)));
    // No provider form: a save would be refused the same way.
    expect(button('Add provider'), findsNothing);
    expect(file.readAsStringSync(), broken);
  });

  testWidgets('a name defaultModel would be cut at is refused in place, and '
      'the file stays as it was', (tester) async {
    const before = '{"providers":[],"defaultModel":"a:b"}\n';
    file.writeAsStringSync(before);
    await pump(tester);
    await tester.tap(button('Add provider'));
    await tester.pump();
    await type(tester, 'Name', 'a:b');
    await type(tester, 'Base URL', 'https://x.example.test');
    await tester.tap(button('Save'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Not saved'), findsOneWidget);
    expect(
      find.textContaining('defaultModel is read at the first'),
      findsOneWidget,
    );
    expect(file.readAsStringSync(), before);
  });

  testWidgets('the live session shows its model and candidates; Refresh '
      'restarts it', (tester) async {
    await pump(
      tester,
      probe: session(
        current: 'openai:gpt-5',
        options: ['openai:gpt-5', 'openai:o3'],
      ),
    );

    expect(find.text('openai:gpt-5'), findsWidgets);
    expect(find.textContaining('openai:o3'), findsOneWidget);
    // Two candidates: the list, and no Refresh (the page shows it when
    // there is at most one — §27.5 ③).
    expect(button('Refresh'), findsNothing);

    await pump(tester, probe: session(current: 'openai:gpt-5'));
    expect(button('Refresh'), findsOneWidget);
    await tester.tap(button('Refresh'));
    expect(restarts, 1);
  });

  testWidgets('editing keeps the key that is there: a blank field writes the '
      'one saved, and the model comes with it', (tester) async {
    file.writeAsStringSync(
      '${jsonEncode({
        'providers': [
          {'name': 'openai', 'baseURL': 'https://old.example.test', 'apiKey': 'sk-old-9999'},
        ],
        'defaultModel': 'openai:gpt-5',
      })}\n',
    );
    await pump(tester);
    await tester.tap(button('Edit'));
    await tester.pump();

    // The key box starts empty (a key is never shown back), the model is
    // the one defaultModel names.
    expect(
      tester.widget<EditableText>(field('API key').first).controller.text,
      isEmpty,
    );
    expect(
      tester.widget<EditableText>(field('Model').first).controller.text,
      'gpt-5',
    );
    await type(tester, 'Base URL', 'https://new.example.test');
    await tester.tap(button('Save'));
    await tester.pump();
    await tester.pump();

    final raw = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect((raw['providers'] as List).single, {
      'name': 'openai',
      'baseURL': 'https://new.example.test',
      'apiKey': 'sk-old-9999',
    });
    expect(raw['defaultModel'], 'openai:gpt-5');
  });

  testWidgets('a providers that is not a list is replaced by one, and the page '
      'says so', (tester) async {
    file.writeAsStringSync('{"providers":{"x":1},"defaultModel":"a:b"}\n');
    await pump(tester);
    await tester.tap(button('Add provider'));
    await tester.pump();
    await type(tester, 'Name', 'openai');
    await type(tester, 'Base URL', 'https://api.example.com');
    await type(tester, 'Model', 'gpt-5');
    await tester.tap(button('Save'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('was not a list'), findsOneWidget);
    final raw = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect((raw['providers'] as List).single, {
      'name': 'openai',
      'baseURL': 'https://api.example.com',
      'apiKey': '',
    });
  });

  testWidgets('editing a provider that is not the default, with the model '
      'left blank, is refused — the default model stays as it was', (
    tester,
  ) async {
    const before =
        '{"providers":[{"name":"a","baseURL":"https://a.example.test",'
        '"apiKey":"k-a"},{"name":"b","baseURL":"https://b.example.test",'
        '"apiKey":"k-b"}],"defaultModel":"a:gpt-5"}\n';
    file.writeAsStringSync(before);
    await pump(tester);
    // The model box comes empty for a provider defaultModel does not name.
    await tester.tap(button('Edit').at(1));
    await tester.pump();
    expect(
      tester.widget<EditableText>(field('Model').first).controller.text,
      isEmpty,
    );
    await tester.tap(button('Save'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Not saved'), findsOneWidget);
    expect(find.textContaining('the model is empty'), findsOneWidget);
    // Nothing was written: the model a session starts with is still a's.
    expect(file.readAsStringSync(), before);
  });

  testWidgets('a name already there is said to update that provider, and it '
      'does — one entry, not two', (tester) async {
    file.writeAsStringSync(
      '${jsonEncode({
        'providers': [
          {'name': 'openai', 'baseURL': 'https://old.example.test', 'apiKey': 'sk-old-9999'},
        ],
        'defaultModel': 'openai:gpt-5',
      })}\n',
    );
    await pump(tester);
    await tester.tap(button('Add provider'));
    await tester.pump();
    await type(tester, 'Name', 'openai');
    // Said before the save (§27.4: not silently overwritten).
    expect(find.textContaining('already there'), findsOneWidget);
    expect(find.textContaining('Saving updates it'), findsOneWidget);
    await type(tester, 'Base URL', 'https://new.example.test');
    await type(tester, 'Model', 'gpt-5');
    await tester.tap(button('Save'));
    await tester.pump();
    await tester.pump();

    final raw = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final providers = (raw['providers'] as List).cast<Map<String, Object?>>();
    expect(providers, hasLength(1));
    expect(providers.single['baseURL'], 'https://new.example.test');
    // The key left blank kept the one there (D115).
    expect(providers.single['apiKey'], 'sk-old-9999');
  });

  testWidgets('with no session open there is nothing to reopen', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(button('Add provider'));
    await tester.pump();
    await type(tester, 'Name', 'openai');
    await type(tester, 'Base URL', 'https://api.example.com');
    await type(tester, 'Model', 'gpt-5');
    await tester.tap(button('Save'));
    await tester.pump();
    await tester.pump();

    // The word is still said; the button has nothing to call.
    expect(
      find.textContaining('Saved. The model choices update'),
      findsOneWidget,
    );
    expect(
      tester.widget<IdeButton>(button('Reopen thincoder session')).onPressed,
      isNull,
    );
  });
}
