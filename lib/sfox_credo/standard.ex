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

  config_file = Path.join(__DIR__, "standard_config.exs")
  @config File.read!(config_file)
  @external_resource config_file

  # coveralls-ignore-start
  @doc false
  def init(exec) do
    register_default_config(exec, @config)
  end

  # coveralls-ignore-stop
end
