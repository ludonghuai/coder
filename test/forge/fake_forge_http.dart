import 'dart:convert';

import 'package:baocode/forge/forge_api.dart';

/// Answers requests by method and URL (its path and query), and keeps
/// them.
class FakeForgeHttp implements ForgeHttp {
  final Map<String, Object? Function(FakeRequest request)> routes = {};
  final List<FakeRequest> requests = [];

  void on(String method, String url, Object? Function(FakeRequest) answer) =>
      routes['$method $url'] = answer;

  @override
  Future<ForgeResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    Object? json,
    Map<String, String>? form,
  }) async {
    final request = FakeRequest(method, url, headers, json, form);
    requests.add(request);
    final key = '$method ${url.toString()}';
    final route =
        routes[key] ??
        routes['$method ${url.replace(query: '').toString().replaceAll('?', '')}'];
    if (route == null) {
      return const ForgeResponse(404, '{"message":"Not Found"}');
    }
    return switch (route(request)) {
      final ForgeResponse response => response,
      final answer => ForgeResponse(200, jsonEncode(answer)),
    };
  }
}

class FakeRequest {
  FakeRequest(this.method, this.url, this.headers, this.json, this.form);

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final Object? json;
  final Map<String, String>? form;
}
