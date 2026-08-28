import 'package:hydrowin/app/cloud_scope.dart';
import 'package:flutter/widgets.dart';

/// Собирает абсолютный URL для `/v1/media/...` путей с API.
String resolveMediaUrl(BuildContext context, String? path) {
  if (path == null || path.isEmpty) return '';
  if (path.startsWith('http')) return path;
  final base = Uri.parse(CloudScope.of(context).api.baseUrl);
  return Uri(
    scheme: base.scheme,
    host: base.host,
    port: base.hasPort ? base.port : null,
    path: path,
  ).toString();
}
