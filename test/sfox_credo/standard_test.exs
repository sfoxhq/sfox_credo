defmodule SfoxCredo.StandardTest do
  use ExUnit.Case, async: true

  alias Credo.CLI.Options
  alias Credo.Execution
  alias Credo.Execution.Task.InitializePlugins
  alias SfoxCredo.Standard

  test "registers under `default` without `--config-name`" do
    assert config_names(init(nil)) == ["default"]
  end

  test "registers under the `--config-name` in effect" do
    assert config_names(init(%Options{switches: %{config_name: "ci"}})) == ["ci"]
  end

  defp init(cli_options) do
    InitializePlugins.call(%{Execution.build() | plugins: [{Standard, []}], cli_options: cli_options}, [])
  end

  # The standard config calls a function, so it is evaluated rather than parsed.
  defp config_names(exec) do
    assert [{:plugin, Standard, config}] = Execution.get_config_files(exec)
    assert {:ok, %{configs: configs}} = Credo.ExsLoader.parse(config, "nofile", exec, false)

    for %{name: name, checks: %{extra: [_ | _]}} <- configs, do: name
  end
end
