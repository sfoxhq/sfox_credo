defmodule SfoxCredo.Standard do
  @moduledoc """
  Default _standard_ Credo checks used for Elixir projects at sFOX.

  ## Setup

  Add to your `.credo.exs`:

  ```elixir
  %{configs: [%{name: "default", plugins: [{SfoxCredo.Standard, []}]}]}
  ```

  Credo will not merge `extra` checks from plugins when `checks.enabled` is specified, so
  the configuration must be copied when provided otherwise.
  """

  import Credo.Plugin

  alias SfoxCredo.PluginConfig

  config_file = Path.join(__DIR__, "standard_config.exs")
  @config File.read!(config_file)
  @external_resource config_file

  # The config is registered under the config name in effect, so it also applies with
  # `--config-name`; the config file reads it from the `config_name` binding.
  @doc false
  def init(exec) do
    register_default_config(exec, "config_name = #{inspect(PluginConfig.config_name(exec))}\n" <> @config)
  end
end
