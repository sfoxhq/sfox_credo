# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/sfox_credo/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule SfoxCredo.Custom do
  @moduledoc """
  Custom Credo checks used for Elixir projects at sFOX.

  ## Setup

  Add to your `.credo.exs`:

  ```elixir
  %{configs: [%{name: "default", plugins: [{SfoxCredo.Custom, []}]}]}
  ```

  ## Selecting checks

  Each check belongs to one group, given by its Credo tag:

  - `:ash` (disabled by default)

    - `SfoxCredo.Check.Refactor.AshCallInEnum`

  - `:correctness` (enabled by default)

    - `SfoxCredo.Check.Warning.AvoidAtomToString`

  - `:docs` (enabled by default)

    - `SfoxCredo.Check.Readability.DocFencedCode`
    - `SfoxCredo.Check.Readability.DocHeadingLevel`
    - `SfoxCredo.Check.Readability.DocListStyle`

  - `:ecto` (disabled by default)

    - `SfoxCredo.Check.Design.EctoMigrationTimestamps`

  - `:security` (enabled by default)

    - `SfoxCredo.Check.Warning.LoggerMessageInspect`
    - `SfoxCredo.Check.Warning.LoggerMetadataInspect`

  - `:suppressions` (enabled by default)

    - `SfoxCredo.Check.Readability.DisableWithoutReason`

  Change the selection with the `include` and `exclude` plugin params;
  `exclude` wins when a group is in both:

  ```elixir
  plugins: [{SfoxCredo.Custom, include: [:ecto], exclude: [:docs]}]
  ```

  Checks outside the selection aren't registered, so a single one can still be enabled (or
  configured) in the `extra` list of your `.credo.exs`:

  ```elixir
  checks: %{extra: [{SfoxCredo.Check.Design.EctoMigrationTimestamps, []}]}
  ```

  Any param other than `include` and `exclude`, an unknown group in either, or an
  `include` of `:ash` or `:ecto` when `Ash` or `Ecto` isn't a dependency stops Credo with
  an error and a non-zero exit status. Checks for those groups are only compiled when
  their library is a dependency.

  When the plugin is listed in more than one config file (a project's `.credo.exs` and its
  umbrella's, say), the params of the config closest to the project are used, as with
  every other config setting.

  The checks are registered under the config name in effect, so they also apply with
  `--config-name`.

  Credo will not merge `extra` checks from plugins when `checks.enabled` is specified, so
  the checks must be listed in `enabled` directly in that case.
  """

  import Credo.Plugin

  alias Credo.CLI.ExitStatus
  alias Credo.Execution
  alias SfoxCredo.PluginConfig

  @checks [
    SfoxCredo.Check.Design.EctoMigrationTimestamps,
    SfoxCredo.Check.Readability.DisableWithoutReason,
    SfoxCredo.Check.Readability.DocFencedCode,
    SfoxCredo.Check.Readability.DocHeadingLevel,
    SfoxCredo.Check.Readability.DocListStyle,
    SfoxCredo.Check.Refactor.AshCallInEnum,
    SfoxCredo.Check.Warning.AvoidAtomToString,
    SfoxCredo.Check.Warning.LoggerMessageInspect,
    SfoxCredo.Check.Warning.LoggerMetadataInspect
  ]

  # The library each optional group's checks need.
  @group_dependencies [ash: Ash, ecto: Ecto]

  @groups [:ash, :correctness, :docs, :ecto, :security, :suppressions]
  @default_groups [:correctness, :docs, :security, :suppressions]
  @params [:include, :exclude]

  # Credo concatenates the `plugins` of every config file it reads (root directory first,
  # the project's own config last) and initializes every listing, but its
  # `get_plugin_param/3` reads only the first. The last listing's params are used instead,
  # and the config is registered once.
  @doc false
  def init(exec) do
    with false <- initialized?(exec),
         {:ok, params} <- plugin_params(exec),
         {:ok, include} <- groups_param(params, :include),
         {:ok, exclude} <- groups_param(params, :exclude) do
      selected = Enum.reject(@default_groups ++ include, &(&1 in exclude))
      register_default_config(exec, config(selected, PluginConfig.config_name(exec)))
    else
      true ->
        exec

      :disabled ->
        exec

      {:error, message} ->
        exec
        |> Execution.put_exit_status(ExitStatus.config_loaded_but_invalid())
        |> Execution.halt(message)
    end
  end

  @doc false
  def checks, do: available(@checks)

  @doc false
  # The checks that are compiled; an `:ash` or `:ecto` check isn't when its library is
  # missing.
  def available(checks), do: Enum.filter(checks, &Code.ensure_loaded?/1)

  @doc false
  # An error message when an included group needs a library that isn't a dependency, or
  # `nil`.
  def missing_dependency(groups, dependencies) do
    case for({group, module} <- dependencies, group in groups, not Code.ensure_loaded?(module), do: {group, module}) do
      [] ->
        nil

      missing ->
        names = Enum.map_join(missing, ", ", fn {group, module} -> "#{inspect(group)} needs #{inspect(module)}" end)
        "SfoxCredo.Custom `include` has groups whose library is not a dependency: #{names}"
    end
  end

  @doc false
  def checks(groups) when is_list(groups) do
    Enum.filter(checks(), &selected?(&1, groups))
  end

  def checks(group), do: checks([group])

  @doc false
  def groups, do: @groups

  @doc false
  def default_groups, do: @default_groups

  # An earlier listing has registered the config, or halted on invalid params.
  defp initialized?(exec) do
    exec.halted or Enum.any?(Execution.get_config_files(exec), &match?({:plugin, __MODULE__, _config}, &1))
  end

  # A closer config can turn the plugin off with `{SfoxCredo.Custom, false}`; Credo skips
  # that listing but still initializes the others.
  defp plugin_params(exec) do
    case List.last(for {__MODULE__, params} <- exec.plugins, do: params) do
      false ->
        :disabled

      params when is_list(params) or is_map(params) ->
        case Enum.reject(params, &match?({key, _value} when key in @params, &1)) do
          [] -> {:ok, params}
          unknown -> {:error, "SfoxCredo.Custom accepts only #{inspect(@params)} params, got: #{inspect(unknown)}"}
        end

      params ->
        {:error, "SfoxCredo.Custom params must be a keyword list, got: #{inspect(params)}"}
    end
  end

  defp groups_param(params, key) do
    value = params[key] || []

    cond do
      not (is_list(value) and Enum.all?(value, &(&1 in @groups))) ->
        {:error, "SfoxCredo.Custom `#{key}` must be a list of groups from #{inspect(@groups)}, got: #{inspect(value)}"}

      message = key == :include && missing_dependency(value, @group_dependencies) ->
        {:error, message}

      true ->
        {:ok, value}
    end
  end

  defp config(selected, name) do
    extra = for check <- checks(), selected?(check, selected), do: {check, []}

    inspect(%{configs: [%{name: name, checks: %{extra: extra}}]}, limit: :infinity)
  end

  defp selected?(check, selected), do: Enum.any?(check.tags(), &(&1 in selected))
end
