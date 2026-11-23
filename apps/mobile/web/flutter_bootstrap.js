{{flutter_js}}
{{flutter_build_config}}

const isLoopback = ['localhost', '127.0.0.1', '[::1]'].includes(location.hostname);
_flutter.loader.load(isLoopback ? {
  config: { fontFallbackBaseUrl: new URL('fonts/', document.baseURI).href },
} : undefined);
