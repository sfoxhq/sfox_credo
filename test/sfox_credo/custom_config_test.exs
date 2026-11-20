defmodule SfoxCredo.CustomConfigTest do
  use ExUnit.Case, async: true

  @config_file Path.expand("../../lib/sfox_credo/custom_config.exs", __DIR__)

  defp configured_modules do
    {config, _} = Code.eval_file(@config_file)

    for %{checks: %{extra: extra}} <- config.configs,
        {module, _opts} <- extra,
        do: module
  end

  test "every configured check module exists and is a Credo check" do
    for module <- configured_modules() do
      assert Code.ensure_loaded?(module), "#{inspect(module)} does not exist"

      assert function_exported?(module, :run, 2),
             "#{inspect(module)} is not a Credo check (no run/2)"
    end
  end

  test "every check shipped in lib/ is configured" do
    shipped =
      :sfox_credo
      |> Application.spec(:modules)
      # Shared helpers (alias resolution, Logger call matching, doc scanning) live under
      # `SfoxCredo.Check` too; only modules implementing `Credo.Check` are checks.
      |> Enum.filter(&(String.starts_with?(Macro.to_string(&1), "SfoxCredo.Check.") and credo_check?(&1)))

    assert Enum.sort(shipped) == Enum.sort(configured_modules())
  end

  defp credo_check?(module) do
    behaviours =
      :attributes
      |> module.module_info()
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    Credo.Check in behaviours
  end
end
