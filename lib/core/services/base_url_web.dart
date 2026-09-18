String detectApiBase() {
  // Local tests must never need production credentials or mutate production.
  // Release default is unchanged; preview builds explicitly override it.
  return const String.fromEnvironment('ESEP_API_BASE',
      defaultValue: 'https://api.esepkz.com/api');
}
