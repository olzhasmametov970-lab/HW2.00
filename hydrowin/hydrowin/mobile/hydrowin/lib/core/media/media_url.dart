import 'package:flutter/material.dart';
import 'package:hydrowin/app/cloud_scope.dart';

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

/// Bearer для `/v1/media/*` (эндпоинты требуют JWT).
Future<Map<String, String>> mediaAuthHeaders(BuildContext context) async {
  final token = await CloudScope.of(context).tokens.getAccessToken();
  if (token == null || token.isEmpty) return const {};
  return {'Authorization': 'Bearer $token'};
}

/// Image.network с Authorization — для аватаров/фото станков.
class AuthNetworkImage extends StatelessWidget {
  const AuthNetworkImage({
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorBuilder,
    super.key,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: mediaAuthHeaders(context),
      builder: (context, snap) {
        return Image.network(
          url,
          width: width,
          height: height,
          fit: fit,
          headers: snap.data ?? const {},
          errorBuilder: errorBuilder,
        );
      },
    );
  }
}

/// NetworkImage с JWT для CircleAvatar.backgroundImage.
Future<NetworkImage?> authNetworkImageProvider(
  BuildContext context,
  String url,
) async {
  if (url.isEmpty) return null;
  final headers = await mediaAuthHeaders(context);
  return NetworkImage(url, headers: headers);
}
