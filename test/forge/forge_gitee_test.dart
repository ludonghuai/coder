// Gitee, the third forge: its links and hosts, and signing in with a token
// (design: G1–G15 of docs/design/forge-accounts.md).

import 'package:baocode/forge/forge_accounts.dart';
import 'package:baocode/forge/forge_api.dart';
import 'package:baocode/forge/forge_ref.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'forge_test.dart' show FakeForgeHttp;

void main() {
  group('Gitee links', () {
    test('an issue and a pull request, and where its hosts are', () {
      final issue = ForgeRef.parse('https://gitee.com/o/r/issues/IKLL6H')!;
      expect(issue.repo.kind, ForgeKind.gitee);
      expect(issue.repo.host, 'gitee.com');
      expect(issue.repo.path, 'o/r');
      expect(issue.kind, ForgeItemKind.issue);
      expect(issue.key, 'IKLL6H');
      expect(issue.tag, '#IKLL6H');
      expect(issue.url.toString(), 'https://gitee.com/o/r/issues/IKLL6H');

      final pull = ForgeRef.parse('https://gitee.com/o/r/pulls/597/files')!;
      expect(pull.kind, ForgeItemKind.pull);
      expect(pull.key, '597');
      expect(pull.url.toString(), 'https://gitee.com/o/r/pulls/597');

      // No `/-/` shape of its own; an anchor is no part of an id; an id's
      // letters keep their case.
      expect(ForgeRef.parse('https://gitee.com/o/r/-/issues/1'), isNull);
      expect(
        ForgeRef.parse('https://gitee.com/o/r/issues/IKLL6H#note_1')?.key,
        'IKLL6H',
      );
      expect(
        ForgeRef.parse('https://gitee.com/o/r/issues/IKLl6h')?.key,
        'IKLl6h',
      );

      expect(
        ForgeRepo.fromRemote('git@gitee.com:o/r.git'),
        const ForgeRepo(
          kind: ForgeKind.gitee,
          host: 'gitee.com',
          path: 'o/r',
          scheme: 'https',
        ),
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
      expect(stillGitLab.key, '1');
      expect(ForgeRef.parse('https://github.com/o/r/-/issues/1'), isNull);
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
          expect(request.url.queryParameters['access_token'], 'gitee-x');
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
