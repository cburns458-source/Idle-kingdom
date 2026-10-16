/// Build identity compiled in by `scripts/cf-build.sh`.
const String appBuild = String.fromEnvironment('APP_BUILD', defaultValue: 'dev');

/// `local`, `staging`, or `production`.
const String appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'local');
