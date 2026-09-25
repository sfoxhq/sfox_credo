defmodule SfoxCredo do
  @moduledoc """
  Credo checks used for Elixir projects at sFOX.

  ## Setup

  Add to your `.credo.exs`:

  ```elixir
  %{configs: [%{name: "default", plugins: [{SfoxCredo, []}]}]}
  ```

  Or add individual checks to `checks.enabled` in your configuration.
  """

  import Credo.Plugin

  alias SfoxCredo.Check.Design.EctoSchemaTimestamp
  alias SfoxCredo.Check.Warning.AvoidAtomToString
  alias SfoxCredo.Plugin.ActivationWarning

  @recommended_checks [AvoidAtomToString]

  @checks [
    AvoidAtomToString,
    EctoSchemaTimestamp
  ]

  @default_config "%{configs: [%{name: \"default\", checks: %{extra: #{inspect(Enum.map(@recommended_checks, &{&1, []}))}}}]}"

  # coveralls-ignore-start
  def init(exec) do
    exec
    |> register_default_config(@default_config)
    |> append_task(:validate_config, ActivationWarning)
  end

  def checks, do: @checks
  def recommended_checks, do: @recommended_checks
  # coveralls-ignore-stop
end
