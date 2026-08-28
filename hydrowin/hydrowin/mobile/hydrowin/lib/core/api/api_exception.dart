class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.code});

  final int statusCode;
  final String message;
  final String? code;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
