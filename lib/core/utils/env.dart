import 'package:envied/envied.dart';

part 'env.g.dart';

@Envied(path: '.env')
abstract class Env {
  @EnviedField(varName: 'FDC_API_KEY', obfuscate: true)
  static final String fdcApiKey = _Env.fdcApiKey;
  @EnviedField(varName: 'SENTRY_DNS', obfuscate: true)
  static final String sentryDns = _Env.sentryDns;
  @EnviedField(varName: 'SUPABASE_PROJECT_URL', obfuscate: true)
  static final String supabaseProjectUrl = _Env.supabaseProjectUrl;
  @EnviedField(varName: 'SUPABASE_PROJECT_ANON_KEY', obfuscate: true)
  static final String supabaseProjectAnonKey = _Env.supabaseProjectAnonKey;
  @EnviedField(varName: 'OPENAI_API_KEY', obfuscate: true)
  static final String openAiApiKey = _Env.openAiApiKey;
  @EnviedField(varName: 'OPENAI_MODEL', obfuscate: true) //, defaultValue: 'gpt-3.5-turbo-0125')
  static final String openAiModel = _Env.openAiModel;
  @EnviedField(varName: 'OPENAI_BASE_URL', obfuscate: true) //, defaultValue: 'https://api.openai.com')
  static final String openAiBaseUrl = _Env.openAiBaseUrl;
}
