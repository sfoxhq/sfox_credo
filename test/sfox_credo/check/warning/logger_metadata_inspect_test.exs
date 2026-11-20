# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/sfox_credo/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule SfoxCredo.Check.Warning.LoggerMetadataInspectTest do
  use Credo.Test.Case, async: true

  alias SfoxCredo.Check.Warning.LoggerMetadataInspect

  defp module(body) do
    """
    defmodule CredoSampleModule do
      require Logger

      def run(x, r) do
    #{body}
      end
    end
    """
  end

  defp run(source, params \\ []) do
    source
    |> to_source_file()
    |> run_check(LoggerMetadataInspect, params)
  end

  describe "flags" do
    for {name, body} <- [
          {"a level call", ~S|    Logger.error("failed", reason: inspect(r))|},
          {"Logger.metadata/1", ~S|    Logger.metadata(reason: inspect(r))|},
          {"Logger.log/3", ~S|    Logger.log(:error, "failed", reason: inspect(r))|},
          {"interpolation", ~S|    Logger.error("failed", reason: "got #{inspect(r)}")|},
          {"a pipe", ~S'    Logger.error("failed", reason: r |> inspect())'},
          {"a piped message", ~S'    "failed" |> Logger.error(reason: inspect(r))'},
          {"the deprecated warn level", ~S|    Logger.warn("failed", reason: inspect(r))|},
          {"a map", ~S|    Logger.error("failed", %{reason: inspect(r)})|},
          {"a map given to Logger.metadata/1", ~S|    Logger.metadata(%{reason: inspect(r)})|},
          {"a lazy message's metadata", ~S|    Logger.error(fn -> {"failed", reason: inspect(r)} end)|},
          {"a multi-line lazy message's metadata",
           ~S|    Logger.error(fn -> x = 1; {"failed #{x}", %{reason: inspect(r)}} end)|},
          {"Logger.bare_log/3", ~S|    Logger.bare_log(:error, "failed", reason: inspect(r))|},
          {":logger metadata", ~S|    :logger.error("failed", %{reason: inspect(r)})|},
          {":logger format metadata", ~S|    :logger.error("failed ~p", [x], %{reason: inspect(r)})|},
          {":logger.update_process_metadata/1", ~S|    :logger.update_process_metadata(%{reason: inspect(r)})|},
          {":logger.set_process_metadata/1", ~S|    :logger.set_process_metadata(%{reason: inspect(r)})|}
        ] do
      test "inspect in #{name}" do
        unquote(body)
        |> module()
        |> run()
        |> assert_issue()
      end
    end

    test "each offending key" do
      ~S|    Logger.error("failed", reason: inspect(r), input: inspect(x), id: x)|
      |> module()
      |> run()
      |> assert_issues(fn issues ->
        assert issues
               |> Enum.map(& &1.trigger)
               |> Enum.sort() == ["input", "reason"]
      end)
    end

    test "a bare call after import Logger" do
      ~S"""
      defmodule CredoSampleModule do
        import Logger

        def run(r), do: metadata(reason: inspect(r))
      end
      """
      |> run()
      |> assert_issue()
    end

    test "an extra logger function's keyword list argument" do
      ~S|    MyApp.Custom.Logger.oops("failed", reason: inspect(r))|
      |> module()
      |> run(extra_loggers: [MyApp.Custom.Logger], extra_logger_functions: [oops: 2])
      |> assert_issue()
    end

    test "a metadata-only extra logger function" do
      ~S|    MyApp.Custom.Logger.context(reason: inspect(r))|
      |> module()
      |> run(extra_loggers: [MyApp.Custom.Logger], extra_logger_functions: [context: 1])
      |> assert_issue(fn issue -> assert issue.trigger == "reason" end)
    end

    test "a map argument to a metadata-only extra logger function" do
      ~S|    MyApp.Custom.Logger.context(%{reason: inspect(r)})|
      |> module()
      |> run(extra_loggers: [MyApp.Custom.Logger], extra_logger_functions: [context: 1])
      |> assert_issue()
    end

    test "metadata assigned to a variable, on the assignment line" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(r) do
          meta = [reason: inspect(r)]
          Logger.error("failed", meta)
        end
      end
      """
      |> run()
      |> assert_issue(fn issue -> assert issue.line_no == 5 end)
    end

    test "a metadata value assigned to a variable" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(r) do
          reason = inspect(r)
          Logger.metadata(reason: reason)
        end
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a local wrapper that puts its parameter in a metadata value" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(r), do: log_failure(inspect(r))

        defp log_failure(reason), do: Logger.error("failed", reason: reason)
      end
      """
      |> run()
      |> assert_issue(fn issue -> assert issue.trigger == "reason" end)
    end

    test "a local wrapper that passes its parameter as the metadata" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(r), do: note("failed", reason: inspect(r))

        defp note(text, meta), do: Logger.info(text, meta)
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a local wrapper around Logger.metadata/1" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(r), do: context(%{reason: inspect(r)})

        defp context(meta), do: Logger.metadata(meta)
      end
      """
      |> run()
      |> assert_issue()
    end

    test "keys not in allowed_keys" do
      ~S|    Logger.error("failed", reason: inspect(r), query: inspect(x))|
      |> module()
      |> run(allowed_keys: [:query])
      |> assert_issue(fn issue -> assert issue.trigger == "reason" end)
    end

    test "on the line of the inspect call" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(r) do
          Logger.error("failed",
            id: 1,
            reason: inspect(r)
          )
        end
      end
      """
      |> run()
      |> assert_issue(fn issue -> assert issue.line_no == 7 end)
    end

    test ":logger metadata assigned to a variable" do
      ~S"""
          meta = %{reason: inspect(r)}
          :logger.error("failed", meta)
      """
      |> module()
      |> run()
      |> assert_issue(fn issue -> assert issue.trigger == "reason" end)
    end

    test "a string key not in allowed_keys" do
      ~S|    Logger.error("failed", %{"reason" => inspect(r), "query" => inspect(x)})|
      |> module()
      |> run(allowed_keys: [:query])
      |> assert_issue(fn issue -> assert issue.trigger == "reason" end)
    end

    for {name, body} <- [
          {"a nested keyword list", ~S|    Logger.error("failed", error: [reason: inspect(r)])|},
          {"a nested map", ~S|    Logger.error("failed", error: %{reason: inspect(r)})|},
          {"a tuple", ~S|    Logger.error("failed", error: {:error, inspect(r)})|},
          {"a conditional", ~S|    Logger.error("failed", error: if(x, do: inspect(r)))|},
          {"a list concatenation", ~S|    Logger.error("failed", x ++ [error: inspect(r)])|},
          {"Keyword.merge/2", ~S|    Logger.error("failed", Keyword.merge(x, error: inspect(r)))|},
          {"Keyword.put/3", ~S|    Logger.error("failed", Keyword.put(x, :error, inspect(r)))|},
          {"Keyword.put_new/3", ~S|    Logger.error("failed", Keyword.put_new(x, :error, inspect(r)))|},
          {"a piped Keyword.put/3", ~S'    Logger.error("failed", x |> Keyword.put(:error, inspect(r)))'},
          {"Map.merge/2", ~S|    Logger.error("failed", Map.merge(x, %{error: inspect(r)}))|},
          {"Map.put/3", ~S|    Logger.error("failed", Map.put(x, :error, inspect(r)))|},
          {"Logger.reset_metadata/1", ~S|    Logger.reset_metadata(error: inspect(r))|},
          {":logger metadata from Map.put/3", ~S|    :logger.error("failed", Map.put(x, :error, inspect(r)))|},
          {":logger metadata from a piped Map.put/3", ~S'    :logger.error("failed", x |> Map.put(:error, inspect(r)))'}
        ] do
      test "inspect in #{name}" do
        unquote(body)
        |> module()
        |> run()
        |> assert_issue(fn issue -> assert issue.trigger == "error" end)
      end
    end

    test "a merge of metadata variables" do
      ~S"""
          base = [id: 1]
          extra = %{error: inspect(r)}
          Logger.error("failed", Keyword.merge(base, extra))
      """
      |> module()
      |> run()
      |> assert_issue(fn issue -> assert issue.trigger == "error" end)
    end

    test "a map update of a tainted map" do
      ~S"""
          meta = %{error: inspect(r)}
          Logger.error("failed", %{meta | id: 1})
      """
      |> module()
      |> run()
      |> assert_issue(fn issue -> assert issue.trigger == "error" end)
    end

    test "a keyword variable passed to an extra logger function" do
      ~S"""
          meta = [reason: inspect(r)]
          MyApp.Custom.Logger.context(meta)
      """
      |> module()
      |> run(extra_loggers: [MyApp.Custom.Logger], extra_logger_functions: [context: 1])
      |> assert_issue(fn issue -> assert issue.trigger == "reason" end)
    end

    test "a map update" do
      ~S'    Logger.metadata(%{x | reason: inspect(r)})'
      |> module()
      |> run()
      |> assert_issue(fn issue -> assert issue.trigger == "reason" end)
    end
  end

  describe "does not flag" do
    test "a metadata variable bound by a case pattern" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x) do
          case x do
            {:ok, meta} -> Logger.info("ok", meta)
          end
        end
      end
      """
      |> run()
      |> refute_issues()
    end

    for {name, body} <- [
          {"inspect in the message", ~S|    Logger.error("failed: #{inspect(r)}")|},
          {"inspect in a lazy message", ~S|    Logger.error(fn -> {"failed #{inspect(r)}", id: x} end)|},
          {":logger format arguments", ~S|    :logger.error("failed ~s", [inspect(r)])|},
          {"a plain term", ~S|    Logger.error("failed", reason: r)|},
          {"a variable holding metadata", ~S|    Logger.error("failed", r)|},
          {"Exception.message/1", ~S|    Logger.error("failed", reason: Exception.message(r))|},
          {"an unconfigured logger module", ~S|    MyApp.Custom.Logger.error("failed", reason: inspect(r))|},
          {"a non-logger call", ~S|    Keyword.merge([], reason: inspect(r))|}
        ] do
      test name do
        unquote(body)
        |> module()
        |> run()
        |> refute_issues()
      end
    end

    test "an allowed key reached through a wrapper" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(r), do: log_failure(inspect(r))

        defp log_failure(reason), do: Logger.error("failed", reason: reason)
      end
      """
      |> run(allowed_keys: [:reason])
      |> refute_issues()
    end

    test "a wrapper's message parameter" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(r), do: note("failed #{inspect(r)}")

        defp note(text), do: Logger.info(text, id: 1)
      end
      """
      |> run()
      |> refute_issues()
    end

    test "a metadata variable rebound by a case pattern" do
      ~S"""
          reason = inspect(r)

          case x do
            {:error, reason} -> Logger.error("failed", reason: reason)
          end
      """
      |> module()
      |> run()
      |> refute_issues()
    end

    test ":logger format arguments assigned to a variable" do
      ~S"""
          args = [inspect(r)]
          :logger.error("failed ~s", args)
      """
      |> module()
      |> run()
      |> refute_issues()
    end

    for {name, body} <- [
          {"a merge of unknown values", ~S|    Logger.error("failed", Keyword.merge(x, r))|},
          {"another Keyword function", ~S|    Logger.error("failed", Keyword.delete(x, inspect(r)))|},
          {"a non-literal key", ~S|    Logger.error("failed", Keyword.put(x, r, inspect(r)))|},
          {"a :logger format from another Map function", ~S|    :logger.error("failed ~s", Map.keys(x))|}
        ] do
      test name do
        unquote(body)
        |> module()
        |> run()
        |> refute_issues()
      end
    end

    test "an allowed string key" do
      ~S|    Logger.error("failed", %{"query" => inspect(r)})|
      |> module()
      |> run(allowed_keys: [:query])
      |> refute_issues()
    end

    test "an allowed key" do
      ~S|    Logger.error("failed", reason: inspect(r))|
      |> module()
      |> run(allowed_keys: [:reason])
      |> refute_issues()
    end
  end
end
