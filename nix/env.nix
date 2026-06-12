{...}:
{
  # Git Configuration
  GIT_CONFIG_COUNT = "2";
  GIT_CONFIG_KEY_0 = "include.path";
  GIT_CONFIG_VALUE_0 = "${./.gitconfig}";
  GIT_CONFIG_KEY_1 = "core.excludesFile";
  GIT_CONFIG_VALUE_1 = "${./.gitignore}";

  # Editor
  EDITOR = "nvim";

  # Memory System (mem) configuration
  MEM_ARTIFACT_TYPES = ''["spec", "plan", "trace", "doc", "todo", "bin", "tmp", "ref"]'';
  MEM_IGNORED_TYPES = ''["tmp", "ref"]'';

  # Build and Runtime settings
  CARGO_BUILD_JOBS = "1";
  OPENCODE_ENABLE_EXPERIMENTAL_MODELS = "true";
}
