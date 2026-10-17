// Gitee, the third forge: its links and hosts, its API (design: G1–G15 of
// docs/design/forge-accounts.md), and signing in with a token.

import 'package:baocode/forge/forge_accounts.dart';
import 'package:baocode/forge/forge_api.dart';
import 'package:baocode/forge/forge_ref.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_forge_http.dart';

void main() {
  group('Gitee links', () {
    test('an issue and a pull request, and where its hosts are', () {
      final issue = ForgeRef.parse('https://gitee.com/o/r/issues/IKLL6H')!;
      expect(issue.repo.kind, ForgeKind.gitee);
      expect(issue.repo.host, 'gitee.com');
      expect(issue.repo.path, 'o/r');
      expect(issue.kind, ForgeItemKind.issue);
      expect(issue.number, 'IKLL6H');
      expect(issue.tag, '#IKLL6H');
      expect(issue.url.toString(), 'https://gitee.com/o/r/issues/IKLL6H');

      final pull = ForgeRef.parse('https://gitee.com/o/r/pulls/597/files')!;
      expect(pull.kind, ForgeItemKind.pull);
      expect(pull.number, '597');
      expect(pull.url.toString(), 'https://gitee.com/o/r/pulls/597');

      // No `/-/` shape of its own; its enterprise pages are no repository's;
      // an anchor is no part of an id; an id's letters keep their case.
      expect(ForgeRef.parse('https://gitee.com/o/r/-/issues/1'), isNull);
      expect(
        ForgeRef.parse('https://gitee.com/enterprises/acme/issues/1'),
        isNull,
      );
      expect(
        ForgeRef.parse('https://gitee.com/o/r/issues/IKLL6H#note_1')?.number,
        'IKLL6H',
      );
      expect(
        ForgeRef.parse('https://gitee.com/o/r/issues/IKLl6h')?.number,
        'IKLl6h',
      );

      expect(
        ForgeRepo.fromRemote('git@gitee.com:o/r.git'),
        const ForgeRepo(kind: ForgeKind.gitee, host: 'gitee.com', path: 'o/r'),
      );
      // Ours are owner/name, no more; a GitLab's keeps its sub-groups.
      expect(ForgeRepo.fromRemote('git@gitee.com:o/sub/r.git'), isNull);
      expect(
        ForgeRepo.fromRemote('https://gitlab.com/g/sub/app.git')?.path,
        'g/sub/app',
      );

      // The `/-/` shape stays GitLab's: on GitLab's hosts and on anyone's
      // no account has said the forge of, and on no other forge's.
      final stillGitLab = ForgeRef.parse('https://gitlab.com/o/r/-/issues/1')!;
      expect(stillGitLab.repo.kind, ForgeKind.gitlab);
      expect(stillGitLab.number, '1');
      expect(ForgeRef.parse('https://github.com/o/r/-/issues/1'), isNull);
    });
  });

  group('GiteeApi', () {
    late FakeForgeHttp http;
    late GiteeApi api;
    final repo = const ForgeRepo(
      kind: ForgeKind.gitee,
      host: 'gitee.com',
      path: 'o/r',
    );
    final issue = ForgeRef(
      repo: repo,
      kind: ForgeItemKind.issue,
      number: 'IKLL6H',
    );

    setUp(() {
      http = FakeForgeHttp();
      api = GiteeApi(host: 'gitee.com', http: http, token: () async => 't');
    });

    test('who it is of, with a bearer token', () async {
      http.on('GET', 'https://gitee.com/api/v5/user', (request) {
        expect(request.headers['Authorization'], 'Bearer t');
        return {'login': 'leo', 'name': 'Leo'};
      });
      final me = await api.me();
      expect(me.login, 'leo');
      expect(me.name, 'Leo');
    });

    test('an issue: its state, assignee, labels and comments', () async {
      http.on(
        'GET',
        'https://gitee.com/api/v5/repos/o/r/issues/IKLL6H',
        (_) => {
          'number': 'IKLL6H',
          'title': 'Uploads fail',
          'state': 'progressing',
          'body': 'On 503',
          'user': {'login': 'ann'},
          'assignee': {'login': 'leo'},
          'labels': [
            {'name': 'bug', 'color': 'fd6206'},
          ],
          'comments': 2,
          'updated_at': '2026-10-15T10:00:00+08:00',
        },
      );
      final item = await api.item(issue);
      expect(item.ref.number, 'IKLL6H');
      expect(item.title, 'Uploads fail');
      expect(item.state, ForgeState.open);
      expect(item.body, 'On 503');
      expect(item.author, 'ann');
      expect(item.assignees, ['leo']);
      expect(item.labels, [const ForgeLabel('bug', color: '#fd6206')]);
      expect(item.comments, 2);
      expect(
        item.updated,
        DateTime.parse('2026-10-15T10:00:00+08:00').toLocal(),
      );
      expect(item.checks, isNull);
    });

    test('a rejected issue is closed', () async {
      http.on(
        'GET',
        'https://gitee.com/api/v5/repos/o/r/issues/IKLL6H',
        (_) => {'number': 'IKLL6H', 'title': 'x', 'state': 'rejected'},
      );
      expect((await api.item(issue)).state, ForgeState.closed);
    });

    test(
      'a pull request: merged, draft, its branch; no checks at all',
      () async {
        http
          ..on(
            'GET',
            'https://gitee.com/api/v5/repos/o/r/pulls/597',
            (_) => {
              'number': 597,
              'title': 'Retry uploads',
              'state': 'closed',
              'merged_at': '2026-10-15T10:00:00+08:00',
              'head': {'ref': 'retry-uploads'},
            },
          )
          ..on(
            'GET',
            'https://gitee.com/api/v5/repos/o/r/pulls/598',
            (_) => {
              'number': 598,
              'title': 'Still working',
              'state': 'open',
              'draft': true,
              'head': {'ref': 'wip'},
              'assignees': [
                {'login': 'leo'},
              ],
            },
          );
        final merged = await api.item(
          ForgeRef(repo: repo, kind: ForgeItemKind.pull, number: '597'),
        );
        expect(merged.ref.number, '597');
        expect(merged.state, ForgeState.merged);
        expect(merged.branch, 'retry-uploads');
        expect(merged.checks, isNull);

        final draft = await api.item(
          ForgeRef(repo: repo, kind: ForgeItemKind.pull, number: '598'),
        );
        expect(draft.state, ForgeState.draft);
        expect(draft.branch, 'wip');
        expect(draft.assignees, ['leo']);
        // Its detail carries no comment count, and no checks are asked of
        // it at all: the two requests are the two items'.
        expect(draft.comments, 0);
        expect(draft.checks, isNull);
        expect(http.requests, hasLength(2));
      },
    );

    test(
      'its open issues: the two open states, my login, the newest first',
      () async {
        http
          ..on('GET', 'https://gitee.com/api/v5/user', (_) => {'login': 'leo'})
          ..on('GET', 'https://gitee.com/api/v5/repos/o/r/issues', (request) {
            return switch (request.url.queryParameters['state']) {
              'open' => [
                {
                  'number': 'A1',
                  'title': 'one',
                  'updated_at': '2026-10-14T10:00:00+08:00',
                },
                {
                  'number': 'A2',
                  'title': 'two',
                  'updated_at': '2026-10-16T10:00:00+08:00',
                },
              ],
              _ => [
                {
                  'number': 'B1',
                  'title': 'three',
                  'updated_at': '2026-10-15T10:00:00+08:00',
                },
              ],
            };
          });
        final issues = await api.issues(repo);
        expect(issues.map((item) => item.ref.number), ['A2', 'B1', 'A1']);
        final listed = [
          for (final request in http.requests)
            if (request.url.path.endsWith('/issues')) request,
        ];
        expect(listed, hasLength(2));
        expect(
          {for (final request in listed) request.url.queryParameters['state']},
          {'open', 'progressing'},
        );
        for (final request in listed) {
          expect(request.url.queryParameters['assignee'], 'leo');
          expect(request.url.queryParameters['sort'], 'updated');
          expect(request.url.queryParameters['direction'], 'desc');
          expect(request.url.queryParameters['per_page'], '50');
        }
        // Who it is of is asked once, before anything is listed.
        expect(http.requests.first.url.path, '/api/v5/user');
      },
    );

    test('never more than 50, the oldest of the two lists left out', () async {
      http
        ..on('GET', 'https://gitee.com/api/v5/user', (_) => {'login': 'leo'})
        ..on('GET', 'https://gitee.com/api/v5/repos/o/r/issues', (request) {
          final open = request.url.queryParameters['state'] == 'open';
          return [
            for (var day = 1; day <= 30; day++)
              {
                'number': '${open ? 'O' : 'P'}$day',
                'title': 'x',
                'updated_at':
                    '2026-${open ? '10' : '09'}-'
                    '${day.toString().padLeft(2, '0')}T10:00:00+08:00',
              },
          ];
        });
      final issues = await api.issues(repo);
      expect(issues, hasLength(50));
      expect(issues.first.ref.number, 'O30');
      expect(issues.last.ref.number, 'P11');
    });

    test(
      'created by me and all: who I am is asked only when it is needed',
      () async {
        http
          ..on('GET', 'https://gitee.com/api/v5/user', (_) => {'login': 'leo'})
          ..on('GET', 'https://gitee.com/api/v5/repos/o/r/issues', (_) => []);
        await api.issues(repo, filter: ForgeIssueFilter.created);
        final created = [
          for (final request in http.requests)
            if (request.url.path.endsWith('/issues')) request,
        ];
        expect(created, hasLength(2));
        for (final request in created) {
          expect(request.url.queryParameters['creator'], 'leo');
          expect(request.url.queryParameters.containsKey('assignee'), isFalse);
        }

        http.requests.clear();
        expect(await api.issues(repo, filter: ForgeIssueFilter.all), isEmpty);
        expect(http.requests, hasLength(2));
        for (final request in http.requests) {
          expect(request.url.path.endsWith('/user'), isFalse);
          expect(request.url.queryParameters.containsKey('assignee'), isFalse);
          expect(request.url.queryParameters.containsKey('creator'), isFalse);
        }
      },
    );

    test(
      'a login it refuses stops the list before any of it is asked',
      () async {
        http.on(
          'GET',
          'https://gitee.com/api/v5/user',
          (_) => const ForgeResponse(
            401,
            '{"message":"401 Unauthorized: Access token does not exist"}',
          ),
        );
        await expectLater(
          api.issues(repo),
          throwsA(
            isA<ForgeException>().having(
              (error) => error.unauthorized,
              'unauthorized',
              isTrue,
            ),
          ),
        );
        expect(http.requests, hasLength(1));
        expect(http.requests.single.url.path, '/api/v5/user');
      },
    );

    test('a search word narrows the list', () async {
      http
        ..on('GET', 'https://gitee.com/api/v5/user', (_) => {'login': 'leo'})
        ..on('GET', 'https://gitee.com/api/v5/repos/o/r/issues', (_) => []);
      await api.issues(repo, query: 'upload');
      expect(http.requests, hasLength(3));
      for (final request in http.requests.skip(1)) {
        expect(request.url.queryParameters['q'], 'upload');
      }
    });

    test('a comment on an issue or a pull request; closing an issue', () async {
      http
        ..on(
          'POST',
          'https://gitee.com/api/v5/repos/o/r/issues/IKLL6H/comments',
          (_) => {},
        )
        ..on(
          'POST',
          'https://gitee.com/api/v5/repos/o/r/pulls/597/comments',
          (_) => {},
        )
        ..on(
          'PATCH',
          'https://gitee.com/api/v5/repos/o/issues/IKLL6H',
          (_) => {},
        );
      await api.comment(issue, 'Fixed in #7');
      expect(http.requests.last.method, 'POST');
      expect(
        http.requests.last.url.toString(),
        'https://gitee.com/api/v5/repos/o/r/issues/IKLL6H/comments',
      );
      expect(http.requests.last.json, {'body': 'Fixed in #7'});

      await api.comment(
        ForgeRef(repo: repo, kind: ForgeItemKind.pull, number: '597'),
        'Looks good',
      );
      expect(
        http.requests.last.url.toString(),
        'https://gitee.com/api/v5/repos/o/r/pulls/597/comments',
      );
      expect(http.requests.last.json, {'body': 'Looks good'});

      // Closes by its owner's namespace, naming the repo.
      await api.close(issue);
      expect(http.requests.last.method, 'PATCH');
      expect(
        http.requests.last.url.toString(),
        'https://gitee.com/api/v5/repos/o/issues/IKLL6H',
      );
      expect(http.requests.last.json, {'repo': 'r', 'state': 'closed'});
    });

    test('what it says when it refuses', () async {
      http.on(
        'GET',
        'https://gitee.com/api/v5/user',
        (_) => const ForgeResponse(
          401,
          '{"message":"401 Unauthorized: Access token does not exist"}',
        ),
      );
      await expectLater(
        api.me(),
        throwsA(
          isA<ForgeException>()
              .having(
                (error) => error.message,
                'message',
                '401 Unauthorized: Access token does not exist',
              )
              .having((error) => error.unauthorized, 'unauthorized', isTrue),
        ),
      );
    });
  });

  group('Gitee account', () {
    test('a token it refuses is not kept', () async {
      final http = FakeForgeHttp()
        ..on(
          'GET',
          'https://gitee.com/api/v5/user',
          (_) => const ForgeResponse(
            401,
            '{"message":"401 Unauthorized: Access token does not exist"}',
          ),
        );
      final secrets = MemorySecretStore();
      final accounts = ForgeAccounts(http: http, secrets: secrets);
      await expectLater(
        accounts.signInWithToken(ForgeKind.gitee, 'gitee.com', 'nope'),
        throwsA(isA<ForgeException>()),
      );
      expect(accounts.accounts, isEmpty);
      expect(await secrets.read('forge.gitee.com'), isNull);
    });

    test('a token alone signs it in, and no device flow does', () async {
      final http = FakeForgeHttp()
        ..on('GET', 'https://gitee.com/api/v5/user', (request) {
          expect(request.headers['Authorization'], 'Bearer gitee-x');
          return {'login': 'leo'};
        });
      final secrets = MemorySecretStore();
      Object? kept;
      final accounts = ForgeAccounts(
        http: http,
        secrets: secrets,
        write: (json) async => kept = json,
      );
      expect(
        accounts.canSignInFromBrowser(ForgeKind.gitee, 'gitee.com'),
        isFalse,
      );
      final account = await accounts.signInWithToken(
        ForgeKind.gitee,
        'gitee.com',
        'gitee-x',
      );
      expect(account.kind, ForgeKind.gitee);
      expect(account.login, 'leo');
      expect(accounts.kindOf('gitee.com'), ForgeKind.gitee);
      expect(accounts.apiFor('gitee.com'), isA<GiteeApi>());
      expect(await secrets.read('forge.gitee.com'), contains('gitee-x'));
      expect(kept, isNotEmpty);

      final asked = http.requests.length;
      await expectLater(
        accounts.startDeviceFlow(ForgeKind.gitee),
        throwsA(isA<ForgeException>()),
      );
      expect(http.requests, hasLength(asked));
    });
  });
}
