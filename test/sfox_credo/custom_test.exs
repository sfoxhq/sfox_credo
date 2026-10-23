# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/sfox_credo/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule SfoxCredo.CustomTest do
  use ExUnit.Case, async: true

  alias Credo.CLI.Options
  alias Credo.Execution
  alias Credo.Execution.Task.InitializePlugins
  alias SfoxCredo.Check.Design
  alias SfoxCredo.Check.Readability
  alias SfoxCredo.Check.Refactor
  alias SfoxCredo.Check.Warning
  alias SfoxCredo.Custom

  @ash [Refactor.AshCallInEnum]
  @correctness [Warning.AvoidAtomToString]
  @docs [Readability.DocFencedCode, Readability.DocHeadingLevel, Readability.DocListStyle]
  @ecto [Design.EctoMigrationTimestamps]
  @security [Warning.LoggerMessageInspect, Warning.LoggerMetadataInspect]
  @suppressions [Readability.DisableWithoutReason]

  describe "selection" do
    test "enables correctness, docs, security, and suppressions checks by default" do
      assert selection(init([])) == sorted([@correctness, @docs, @security, @suppressions])
    end

    test "include adds the ecto group" do
      assert selection(init(include: [:ecto])) == sorted([@correctness, @docs, @ecto, @security, @suppressions])
    end

    test "exclude drops a default group" do
      assert selection(init(exclude: [:docs])) == sorted([@correctness, @security, @suppressions])
    end

    test "exclude wins over include" do
      assert selection(init(include: [:ecto], exclude: [:ecto, :security])) ==
               sorted([@correctness, @docs, @suppressions])
    end

    test "excluding every group registers no checks" do
      assert selection(init(exclude: Custom.groups())) == []
    end

    test "an included default group is not enabled twice" do
      enabled = selection(init(include: [:docs]))
      assert enabled == Enum.uniq(enabled)
    end

    test "params may be a map" do
      assert selection(init(%{include: [:ecto]})) == sorted([@correctness, @docs, @ecto, @security, @suppressions])
    end
  end

  describe "listed in more than one config file" do
    test "the last listing's params are used, and the config is registered once" do
      exec = init_plugins([{Custom, []}, {Custom, include: [:ecto]}])

      assert [{:plugin, Custom, _config}] = Execution.get_config_files(exec)
      assert selection(exec) == sorted(Custom.checks(), @ash)
    end

    test "a last listing of `false` registers nothing" do
      assert Execution.get_config_files(init_plugins([{Custom, include: [:ecto]}, {Custom, false}])) == []
    end

    test "invalid params halt once" do
      exec = init_plugins([{Custom, include: [:doc]}, {Custom, include: [:doc]}])

      assert exec.halted
      assert Execution.get_config_files(exec) == []
    end
  end

  describe "config name" do
    test "registers under `default` without `--config-name`" do
      assert config_names(init([])) == ["default"]
    end

    test "registers under the `--config-name` in effect" do
      exec = init_plugins([{Custom, []}], %Options{switches: %{config_name: "ci"}})

      assert config_names(exec) == ["ci"]
    end
  end

  describe "invalid params" do
    for {name, params, pattern} <- [
          {"an unknown include group", [include: [:doc]], "`include` must be a list of groups"},
          {"an unknown exclude group", [exclude: [:logger]], "`exclude` must be a list of groups"},
          {"a bare group instead of a list", [exclude: :docs], "`exclude` must be a list of groups"},
          {"a misspelled param", [includes: [:ecto]], "accepts only [:include, :exclude] params"},
          {"params that aren't a keyword list", :ecto, "params must be a keyword list"}
        ] do
      test "halts Credo for #{name}" do
        exec = init(unquote(params))

        assert exec.halted
        assert Execution.get_exit_status(exec) == Credo.CLI.ExitStatus.config_loaded_but_invalid()
        assert Execution.get_halt_message(exec) =~ "SfoxCredo.Custom"
        assert Execution.get_halt_message(exec) =~ unquote(pattern)
        assert Execution.get_config_files(exec) == []
      end
    end
  end

  # `Ash` and `Ecto` are dependencies here, so a module that doesn't exist stands in for
  # a check or library that isn't compiled.
  describe "optional dependencies" do
    test "only checks that are compiled are available" do
      assert Custom.available([Warning.AvoidAtomToString, SfoxCredo.Check.Refactor.NotCompiled]) ==
               [Warning.AvoidAtomToString]
    end

    test "including a group whose library is missing is an error" do
      assert Custom.missing_dependency([:ash, :docs], ash: NotADependency) ==
               "SfoxCredo.Custom `include` has groups whose library is not a dependency: :ash needs NotADependency"
    end

    test "including a group whose library is present, or not including it, is fine" do
      assert Custom.missing_dependency([:ash], ash: Ash) == nil
      assert Custom.missing_dependency([:docs], ash: NotADependency) == nil
    end
  end

  describe "checks" do
    test "every check shipped in lib/ is in the plugin" do
      shipped =
        :sfox_credo
        |> Application.spec(:modules)
        # Shared helpers live under `SfoxCredo.Check` too; only modules implementing
        # `Credo.Check` are checks.
        |> Enum.filter(&(String.starts_with?(Macro.to_string(&1), "SfoxCredo.Check.") and credo_check?(&1)))

      assert Enum.sort(shipped) == sorted(Custom.checks())
    end

    test "every check is tagged with exactly one known group" do
      for check <- Custom.checks() do
        assert [group] = check.tags(), "#{inspect(check)} has tags #{inspect(check.tags())}"
        assert group in Custom.groups(), "#{inspect(check)} has unknown group #{inspect(group)}"
      end
    end
  end

  describe "documented groups" do
    test "the moduledoc lists every group with its default state and checks" do
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Custom)

      assert documented_groups(moduledoc) == expected_groups()
    end

    test "the README lists every group with its default state and checks" do
      assert documented_groups(File.read!("README.md")) == expected_groups()
    end
  end

  defp credo_check?(module) do
    behaviours =
      :attributes
      |> module.module_info()
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    Credo.Check in behaviours
  end

  defp init(params), do: init_plugins([{Custom, params}])

  defp init_plugins(plugins, cli_options \\ nil) do
    InitializePlugins.call(%{Execution.build() | plugins: plugins, cli_options: cli_options}, [])
  end

  defp selection(exec) do
    assert [{:plugin, Custom, config}] = Execution.get_config_files(exec)
    assert {:ok, %{configs: [%{checks: checks} = config]}} = Credo.ExsLoader.parse(config, "nofile", exec, true)
    assert Map.keys(checks) == [:extra], "unexpected check keys in #{inspect(config)}"

    checks.extra
    |> Enum.map(fn {module, []} -> module end)
    |> Enum.sort()
  end

  defp config_names(exec) do
    assert [{:plugin, Custom, config}] = Execution.get_config_files(exec)
    assert {:ok, %{configs: configs}} = Credo.ExsLoader.parse(config, "nofile", exec, true)

    for %{name: name} <- configs, do: name
  end

  # Each group is a top-level `- `:group` (enabled|disabled by default)` item, followed by
  # the checks in it, until the next line at the left margin.
  defp documented_groups(text) do
    {groups, _current} =
      text
      |> String.split("\n")
      |> Enum.reduce({%{}, nil}, &group_line/2)

    Map.new(groups, fn {key, checks} -> {key, Enum.sort(checks)} end)
  end

  defp group_line(line, {groups, current}) do
    cond do
      match = Regex.run(~r/^- `:(\w+)` \((enabled|disabled) by default\)$/, line, capture: :all_but_first) ->
        [group, state] = match
        key = {String.to_existing_atom(group), state == "enabled"}
        {Map.put(groups, key, []), key}

      is_nil(current) or Regex.match?(~r/^\S/, line) ->
        {groups, nil}

      true ->
        checks = for [check] <- Regex.scan(~r/`(SfoxCredo\.Check\.[\w.]+)`/, line, capture: :all_but_first), do: check
        {Map.update!(groups, current, &(&1 ++ checks)), current}
    end
  end

  defp expected_groups do
    Map.new(Custom.groups(), fn group ->
      checks = for check <- Custom.checks(), group in check.tags(), do: inspect(check)
      {{group, group in Custom.default_groups()}, Enum.sort(checks)}
    end)
  end

  defp sorted(modules, exclude \\ []) do
    modules = List.flatten(modules) -- List.flatten(exclude)
    Enum.sort(modules)
  end
end
