import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/models.dart';

class SseClient {
  final _controller = StreamController<SseEvent>.broadcast();
  HttpClient? _httpClient;
  bool _disposed = false;
  int _connectGen = 0;

  Stream<SseEvent> get stream => _controller.stream;

  void connect(String baseUrl, String token) {
    disconnect();
    _disposed = false;
    final gen = ++_connectGen;
    _loop(baseUrl.trim().replaceAll(RegExp(r'/+$'), ''), token, gen);
  }

  Future<void> _loop(String baseUrl, String token, int gen) async {
    int backoffSec = 2;
    while (!_disposed && gen == _connectGen) {
      try {
        _httpClient?.close(force: true);
        _httpClient = HttpClient();
        final uri = Uri.parse('$baseUrl/api/events?token=${Uri.encodeQueryComponent(token)}');
        final req = await _httpClient!.getUrl(uri);
        req.headers.set('Accept', 'text/event-stream');
        final resp = await req.close();

        if (resp.statusCode == 200) {
          backoffSec = 2;
          await for (final line in resp.transform(utf8.decoder).transform(const LineSplitter())) {
            if (_disposed || gen != _connectGen) break;
            if (line.startsWith('data:')) {
              final raw = line.substring(5).trim();
              if (raw.isEmpty) continue;
              try {
                final map = jsonDecode(raw) as Map<String, dynamic>;
                _controller.add(SseEvent.fromJson(map));
              } catch (_) {}
            }
          }
        }
      } catch (_) {
        // 断线后指数退避重连
      }
      if (_disposed || gen != _connectGen) break;
      await Future.delayed(Duration(seconds: backoffSec));
      backoffSec = (backoffSec * 2).clamp(2, 30);
    }
  }

  void disconnect() {
    _connectGen++;
    _httpClient?.close(force: true);
    _httpClient = null;
  }

  void dispose() {
    _disposed = true;
    disconnect();
    _controller.close();
  }
}
