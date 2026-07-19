class AppConfig {
  const AppConfig({required this.apiBaseUrl, required this.authToken});

  factory AppConfig.fromEnvironment() {
    return const AppConfig(
      apiBaseUrl: String.fromEnvironment('API_BASE_URL'),
      authToken: String.fromEnvironment('AUTH_TOKEN'),
    );
  }

  final String apiBaseUrl;
  final String authToken;

  bool get isDemo => apiBaseUrl.trim().isEmpty;
}
