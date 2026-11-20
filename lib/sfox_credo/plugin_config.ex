defmodule SfoxCredo.PluginConfig do
  @moduledoc false

  # Shared by the `SfoxCredo.Standard` and `SfoxCredo.Custom` plugins.

  alias Credo.Execution

  @doc false
  # The config name in effect. Credo looks a plugin's config up by this name, so a plugin
  # config registered only as `"default"` contributes nothing under `--config-name`.
  # Plugins initialize after Credo has parsed the command line.
  @spec config_name(Execution.t()) :: String.t()
  def config_name(%Execution{cli_options: %{switches: %{config_name: name}}}) when is_binary(name), do: name
  def config_name(%Execution{}), do: "default"
end
