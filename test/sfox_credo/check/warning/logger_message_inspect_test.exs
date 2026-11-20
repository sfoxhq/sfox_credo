# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/sfox_credo/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule SfoxCredo.Check.Warning.LoggerMessageInspectTest do
  use Credo.Test.Case, async: true

  alias SfoxCredo.Check.LoggerCalls
  alias SfoxCredo.Check.Warning.LoggerMessageInspect

  defp module(body) do
    """
    defmodule CredoSampleModule do
      require Logger

      def run(x, e) do
    #{body}
      end
    end
    """
  end

  defp run(source, params \\ []) do
    source
    |> to_source_file()
    |> run_check(LoggerMessageInspect, params)
  end

  describe "flags" do
    for {name, body} <- [
          {"interpolation", ~S|    Logger.error("a #{inspect(x)}")|},
          {"concatenation", ~S|    Logger.error("a " <> inspect(x))|},
          {"a lazy message", ~S|    Logger.warning(fn -> "a #{inspect(x)}" end)|},
          {"a lazy {message, metadata} tuple", ~S|    Logger.warning(fn -> {"a #{inspect(x)}", e: e} end)|},
          {"Logger.log/2", ~S|    Logger.log(:info, inspect(x))|},
          {"Logger.log/3", ~S|    Logger.log(:info, inspect(x), e: e)|},
          {"a chardata list", ~S|    Logger.error(["a: ", inspect(x)])|},
          {"the deprecated warn level", ~S|    Logger.warn("a #{inspect(x)}")|},
          {"a piped message", ~S'    "a #{inspect(x)}" |> Logger.error()'},
          {"a message piped through inspect", ~S'    x |> inspect() |> Logger.error()'},
          {"Kernel.inspect", ~S|    Logger.error("a #{Kernel.inspect(x)}")|},
          {"inspect/2", ~S|    Logger.error("a #{inspect(x, pretty: true)}")|},
          {"Elixir.Logger", ~S|    Elixir.Logger.error("a #{inspect(x)}")|},
          {"Logger.bare_log/2", ~S|    Logger.bare_log(:info, "a #{inspect(x)}")|},
          {"Logger.bare_log/3", ~S|    Logger.bare_log(:info, "a #{inspect(x)}", e: e)|},
          {":logger with a string", ~S|    :logger.error("a #{inspect(x)}")|},
          {":logger with metadata", ~S|    :logger.error("a #{inspect(x)}", %{e: e})|},
          {":logger format arguments", ~S|    :logger.error("a ~s", [inspect(x)])|},
          {":logger format arguments and metadata", ~S|    :logger.error("a ~s", [inspect(x)], %{e: e})|},
          {":logger report values", ~S|    :logger.error(%{what: :failed, reason: inspect(x)})|},
          {":logger.log/3", ~S|    :logger.log(:info, "a ~s", [inspect(x)])|}
        ] do
      test "inspect in #{name}" do
        unquote(body)
        |> module()
        |> run()
        |> assert_issue()
      end
    end

    test "every level" do
      for level <- ~w(emergency alert critical error warning warn notice info debug) do
        ~s|    Logger.#{level}("a \#{inspect(x)}")|
        |> module()
        |> run()
        |> assert_issue()
      end
    end

    test "a call through an alias" do
      ~S"""
      defmodule CredoSampleModule do
        alias Logger, as: L

        def run(x), do: L.error("a #{inspect(x)}")
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a call through require with as:" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger, as: L

        def run(x), do: L.error("a #{inspect(x)}")
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a call through a root-level alias in a later module" do
      ~S"""
      alias Logger, as: L

      defmodule CredoSampleModule do
        def run(x), do: L.error("a #{inspect(x)}")
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a bare call after a root-level import" do
      ~S"""
      import Logger

      defmodule CredoSampleModule do
        def run(x), do: error("a #{inspect(x)}")
      end
      """
      |> run()
      |> assert_issue()
    end

    test "an extra logger required as Logger" do
      ~S"""
      defmodule CredoSampleModule do
        require My.Custom.Logger, as: Logger

        def run(x), do: Logger.error("a #{inspect(x)}")
      end
      """
      |> run(extra_loggers: [My.Custom.Logger])
      |> assert_issue()
    end

    test "a call through an alias of a required Logger" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger
        alias Logger, as: L

        def run(x), do: L.error("a #{inspect(x)}")
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a bare call after import Logger" do
      ~S"""
      defmodule CredoSampleModule do
        import Logger

        def run(x), do: error("a #{inspect(x)}")
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a bare call imported with only:" do
      ~S"""
      defmodule CredoSampleModule do
        import Logger, only: [error: 1]

        def run(x), do: error("a #{inspect(x)}")
      end
      """
      |> run()
      |> assert_issue()
    end

    test "an extra logger module" do
      ~S|    MyApp.Custom.Logger.error("a #{inspect(x)}")|
      |> module()
      |> run(extra_loggers: [MyApp.Custom.Logger])
      |> assert_issue()
    end

    test "an aliased extra logger module" do
      ~S"""
      defmodule CredoSampleModule do
        alias MyApp.Custom.Logger

        def run(x), do: Logger.error("a #{inspect(x)}")
      end
      """
      |> run(extra_loggers: [MyApp.Custom.Logger])
      |> assert_issue()
    end

    test "an imported extra logger module" do
      ~S"""
      defmodule CredoSampleModule do
        import MyApp.Custom.Logger

        def run(x), do: error("a #{inspect(x)}")
      end
      """
      |> run(extra_loggers: [MyApp.Custom.Logger])
      |> assert_issue()
    end

    test "an extra logger function" do
      ~S|    Logger.oops("a #{inspect(x)}")|
      |> module()
      |> run(extra_logger_functions: [oops: 1])
      |> assert_issue()
    end

    test "any non-metadata argument of an extra logger function" do
      ~S|    MyApp.Custom.Logger.notify(:error, "a #{inspect(x)}", e: e)|
      |> module()
      |> run(extra_loggers: [MyApp.Custom.Logger], extra_logger_functions: [notify: 3])
      |> assert_issue()
    end

    test "a message assigned to a variable, on the assignment line" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x) do
          msg = "a #{inspect(x)}"
          Logger.error(msg)
        end
      end
      """
      |> run()
      |> assert_issue(fn issue -> assert issue.line_no == 5 end)
    end

    test "a variable interpolated into the message" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x) do
          detail = inspect(x)
          Logger.error("a #{detail}")
        end
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a chain of variables" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x) do
          detail = inspect(x)
          msg = "a " <> detail
          Logger.error(msg)
        end
      end
      """
      |> run()
      |> assert_issue()
    end

    test "one inspect reaching two calls once" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x) do
          msg = "a #{inspect(x)}"
          Logger.error(msg)
          Logger.info(msg)
        end
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a variable inside a fn body" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(xs) do
          Enum.each(xs, fn x ->
            msg = "a #{inspect(x)}"
            Logger.error(msg)
          end)
        end
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a local wrapper" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x), do: send_message(:error, "a #{inspect(x)}")

        defp send_message(level, text), do: Logger.log(level, "[svc] " <> text)
      end
      """
      |> run()
      |> assert_issue(fn issue -> assert issue.line_no == 4 end)
    end

    test "a local wrapper that passes its parameter through a variable" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x), do: send_message("a #{inspect(x)}")

        defp send_message(text) do
          line = "[svc] #{text}"
          Logger.info(line)
        end
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a wrapper of a wrapper" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x), do: outer("a #{inspect(x)}")

        defp outer(text), do: inner(:error, text)
        defp inner(level, text), do: Logger.log(level, text)
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a wrapper with a default argument, called at the shorter arity" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x), do: note("a #{inspect(x)}")

        defp note(text, level \\ :info), do: Logger.log(level, text)
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a piped call to a local wrapper" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x), do: "a #{inspect(x)}" |> note()

        defp note(text), do: Logger.info(text)
      end
      """
      |> run()
      |> assert_issue()
    end

    test "on the line of the inspect call" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x) do
          Logger.error(
            "a #{inspect(x)}"
          )
        end
      end
      """
      |> run()
      |> assert_issue(fn issue -> assert issue.line_no == 6 end)
    end

    test "a call in the module body" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger
        Logger.info("compiling #{inspect(__MODULE__)}")
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a call in a rescue clause" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(f) do
          f.()
        rescue
          e -> Logger.error("failed: #{inspect(e)}")
        end
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a call in a definition with an unquoted name" do
      ~S"""
      defmodule CredoSampleModule do
        defmacro define(name) do
          quote do
            def unquote(name)(x), do: Logger.info("a #{inspect(x)}")
          end
        end
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a zero-arity definition without parentheses" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run do
          msg = "a #{inspect(self())}"
          Logger.info(msg)
        end
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a variable used in a pinned match keeps its taint" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x, y) do
          msg = "a #{inspect(x)}"
          ^msg = y
          Logger.error(msg)
        end
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a parenthesized block as the message" do
      ~S'    Logger.error((detail = inspect(x); "a #{detail}"))'
      |> module()
      |> run()
      |> assert_issue()
    end

    test "a lazy message ending in an assignment" do
      ~S'    Logger.warning(fn -> msg = "a #{inspect(x)}" end)'
      |> module()
      |> run()
      |> assert_issue()
    end

    test "a message piped through Kernel.inspect" do
      ~S'    x |> Kernel.inspect() |> Logger.error()'
      |> module()
      |> run()
      |> assert_issue()
    end

    test "a :logger report built by map update" do
      ~S'    :logger.error(%{e | reason: inspect(x)})'
      |> module()
      |> run()
      |> assert_issue()
    end

    test "a bare call imported with only: :macros" do
      ~S"""
      defmodule CredoSampleModule do
        import Logger, only: :macros

        def run(x), do: error("a #{inspect(x)}")
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a call after alias __MODULE__" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger
        alias __MODULE__

        def run(x), do: Logger.error("a #{inspect(x)}")
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a call after require with options but no as:" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger, warn: false

        def run(x), do: Logger.error("a #{inspect(x)}")
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a wrapper with a pattern parameter and a guard" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x), do: note({:ok, 1}, "a #{inspect(x)}")

        defp note({:ok, _}, text) when is_binary(text), do: Logger.info(text)
      end
      """
      |> run()
      |> assert_issue()
    end

    test "wrappers nested five deep" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x), do: w5("a #{inspect(x)}")

        defp w5(t), do: w4(t)
        defp w4(t), do: w3(t)
        defp w3(t), do: w2(t)
        defp w2(t), do: w1(t)
        defp w1(t), do: Logger.info(t)
      end
      """
      |> run()
      |> assert_issue()
    end

    for {name, body} <- [
          {"a keyword report", ~S|    Logger.info(event: :failed, reason: inspect(x))|},
          {"a map report", ~S|    Logger.info(%{event: :failed, reason: inspect(x)})|},
          {"a :logger keyword report", ~S|    :logger.error(event: :failed, reason: inspect(x))|},
          {"a :logger report with metadata", ~S|    :logger.error([reason: inspect(x)], %{e: e})|}
        ] do
      test "inspect in #{name}" do
        unquote(body)
        |> module()
        |> run()
        |> assert_issue()
      end
    end

    for {name, body} <- [
          {"a sigil", ~S|    Logger.error(~s(a "#{inspect(x)}"))|},
          {"a nested report value", ~S|    Logger.info(event: :failed, error: [reason: inspect(x)])|},
          {"a tuple in a report", ~S|    Logger.info(result: {:error, inspect(x)})|},
          {"a larger tuple in a report", ~S|    Logger.info(result: {:error, :x, inspect(x)})|},
          {"a struct in a report", ~S|    Logger.info(result: %Err{reason: inspect(x)})|},
          {"an improper chardata list", ~S'    Logger.error(["a: " | inspect(x)])'},
          {"an if expression", ~S|    Logger.error(if e, do: "a", else: inspect(x))|},
          {"an unless expression", ~S|    Logger.error(unless e, do: inspect(x))|},
          {"a case expression", ~S|    Logger.error(case e do {:ok, v} -> v; _ -> inspect(x) end)|},
          {"a cond expression", ~S|    Logger.error(cond do e -> inspect(x); true -> "a" end)|}
        ] do
      test "inspect in #{name}" do
        unquote(body)
        |> module()
        |> run()
        |> assert_issue()
      end
    end

    test "a variable assigned a conditional" do
      ~S"""
          msg = if e, do: "a", else: inspect(x)
          Logger.error(msg)
      """
      |> module()
      |> run()
      |> assert_issue()
    end

    test "a tainted variable used in a cond clause" do
      ~S"""
          msg = inspect(x)

          cond do
            msg != "" -> Logger.error(msg)
          end
      """
      |> module()
      |> run()
      |> assert_issue()
    end

    for {name, format} <- [
          {"~p", ~S|"a ~p"|},
          {"~P", ~S|"a ~P"|},
          {"~w", ~S|"a ~w"|},
          {"~W", ~S|"a ~W"|},
          {"~tp", ~S|"a ~tp"|},
          {"~10.2p", ~S|"a ~10.2p"|},
          {"~-10..*p", ~S|"a ~-10..*p"|},
          {"a charlist", ~S|'a ~p'|},
          {"a ~c sigil", ~S|~c"a ~p"|},
          {"an interpolated string", ~S|"a #{e} ~p"|}
        ] do
      test ":logger format with #{name}" do
        ~s|    :logger.error(#{unquote(format)}, [x])|
        |> module()
        |> run()
        |> assert_issue(fn issue -> assert issue.trigger =~ ~r/^~.*[pPwW]$/ end)
      end
    end

    test ":logger.log/4 format with metadata" do
      ~S|    :logger.log(:info, "a ~p", [x], %{e: e})|
      |> module()
      |> run()
      |> assert_issue(fn issue -> assert issue.trigger == "~p" end)
    end

    test "a wrapper inside a defimpl" do
      ~S"""
      defimpl CredoSample.Proto, for: CredoSample.Type do
        require Logger

        def run(x), do: note(inspect(x))

        defp note(text), do: Logger.info(text)
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a report assigned to a variable" do
      ~S"""
          report = [reason: inspect(x)]
          Logger.info(report)
      """
      |> module()
      |> run()
      |> assert_issue()
    end

    test "a wrapper with defaults declared on a bodiless head" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x), do: log_error("a #{inspect(x)}")

        defp log_error(msg, meta \\ [])
        defp log_error(msg, meta), do: Logger.error(msg, meta)
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a wrapper with a leading default, called at the shorter arity" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x), do: say("a #{inspect(x)}")

        defp say(level \\ :info, msg), do: Logger.log(level, msg)
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a wrapper in a nested module" do
      ~S"""
      defmodule CredoSampleModule do
        defmodule Inner do
          require Logger

          def run(x), do: note("a #{inspect(x)}")

          defp note(text), do: Logger.info(text)
        end
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a wrapper with a bodiless head in an atom-named module" do
      ~S"""
      defmodule :credo_sample_module do
        require Logger

        def run(x), do: note("a #{inspect(x)}")

        defp note(text)
        defp note(text), do: Logger.info(text)
      end
      """
      |> run()
      |> assert_issue()
    end

    test "Logger after a sibling module's nested Logger module ends" do
      ~S"""
      defmodule CredoSampleModule.A do
        defmodule Logger do
        end
      end

      defmodule CredoSampleModule.B do
        require Logger

        def run(x), do: Logger.error("a #{inspect(x)}")
      end
      """
      |> run()
      |> assert_issue()
    end

    test "an outer module's alias inside a nested module" do
      ~S"""
      defmodule CredoSampleModule do
        alias Logger, as: L

        defmodule Inner do
          def run(x), do: L.error("a #{inspect(x)}")
        end
      end
      """
      |> run()
      |> assert_issue()
    end

    test "an alias in a one-line module, which never ends" do
      ~S"""
      defmodule CredoSampleModule.A, do: alias(Logger, as: L)

      defmodule CredoSampleModule.B do
        def run(x), do: L.error("a #{inspect(x)}")
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a call in a module named with an Elixir prefix" do
      ~S"""
      defmodule Elixir.CredoSampleModule do
        require Logger

        def run(x), do: Logger.info("a #{inspect(x)}")
      end
      """
      |> run()
      |> assert_issue()
    end

    test "an extra logger function imported from an extra logger" do
      ~S"""
      defmodule CredoSampleModule do
        import MyApp.Custom.Logger

        def run(x), do: context("a #{inspect(x)}")
      end
      """
      |> run(extra_loggers: [MyApp.Custom.Logger], extra_logger_functions: [context: 1])
      |> assert_issue()
    end

    test "an extra logger aliased through an earlier alias" do
      ~S"""
      defmodule CredoSampleModule do
        alias MyApp.Custom
        alias Custom.Logger, as: L

        def run(x), do: L.error("a #{inspect(x)}")
      end
      """
      |> run(extra_loggers: [MyApp.Custom.Logger])
      |> assert_issue()
    end

    test "a variable bound by a case pattern from a tainted value" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x) do
          msg = inspect(x)

          case x do
            {:ok, other} -> Logger.error(msg <> other)
          end
        end
      end
      """
      |> run()
      |> assert_issue()
    end

    test "a with else clause, which sees the outer binding" do
      ~S"""
          msg = inspect(x)
          with {:ok, msg} <- e.() do
            Logger.info(msg)
          else
            _ -> Logger.info(msg)
          end
      """
      |> module()
      |> run()
      |> assert_issue(fn issue -> assert issue.line_no == 5 end)
    end
  end

  describe "does not flag" do
    for {name, body} <- [
          {"a case clause", ~S|    case e do {:error, msg} -> Logger.error(msg) end|},
          {"a case clause with a guard", ~S|    case e do msg when is_binary(msg) -> Logger.error(msg) end|},
          {"a receive clause", ~S|    receive do msg -> Logger.error(msg) end|},
          {"a rescue clause", ~S|    try do e.() rescue msg -> Logger.error(msg) end|},
          {"a for generator", ~S|    for msg <- e, do: Logger.info(msg)|},
          {"a bitstring generator", ~S|    for <<msg <- e>>, do: Logger.info(msg)|},
          {"a with clause", ~S|    with {:ok, msg} <- e.(), do: Logger.info(msg)|},
          {"a with match clause", ~S|    with msg = e.(), do: Logger.info(msg)|},
          {"a fn clause", ~S|    Enum.each(e, fn msg -> Logger.info(msg) end)|}
        ] do
      test "a tainted variable rebound by #{name}" do
        ("    msg = inspect(x)\n" <> unquote(body))
        |> module()
        |> run()
        |> refute_issues()
      end
    end

    test "a wrapper with the same name in another module" do
      ~S"""
      defmodule CredoSampleModule.A do
        require Logger

        def send(msg), do: Logger.info(msg)
      end

      defmodule CredoSampleModule.B do
        def run(x), do: send(inspect(x))

        defp send(_x), do: :ok
      end
      """
      |> run()
      |> refute_issues()
    end

    test "a local function shadowing an extra logger function after import Logger" do
      ~S"""
      defmodule CredoSampleModule do
        import Logger

        def run(x), do: context("a #{inspect(x)}")

        defp context(text), do: text
      end
      """
      |> run(extra_loggers: [MyApp.Custom.Logger], extra_logger_functions: [context: 1])
      |> refute_issues()
    end

    test "a nested module named Logger" do
      ~S"""
      defmodule CredoSampleModule do
        defmodule Logger do
          def error(text), do: text
        end

        def run(x), do: Logger.error("a #{inspect(x)}")
      end
      """
      |> run()
      |> refute_issues()
    end

    for {name, body} <- [
          {"an uppercase sigil", ~S|    Logger.error(~S"a #{inspect(x)}")|},
          {"a function call taking a string", ~S|    Logger.error(pad("a #{inspect(x)}", []))|},
          {"a :logger format with ~s", ~S|    :logger.error("a ~s", [x])|},
          {"a :logger format with an escaped tilde", ~S|    :logger.error("a ~~p", [x])|},
          {"a :logger string without arguments", ~S|    :logger.error("a ~p")|},
          {"a :logger format in a variable", ~S|    :logger.error(e, [x])|},
          {"a :logger report map", ~S|    :logger.error(%{a: x}, %{e: e})|},
          {"a Logger message with ~p", ~S|    Logger.error("a ~p")|}
        ] do
      test name do
        unquote(body)
        |> module()
        |> run()
        |> refute_issues()
      end
    end

    test "a variable rebound by a case pattern in a case expression" do
      ~S"""
          msg = inspect(x)
          Logger.error(case e do msg -> msg end)
      """
      |> module()
      |> run()
      |> refute_issues()
    end

    test "a keyword variable passed to an extra logger function" do
      ~S"""
          meta = [reason: inspect(x)]
          MyApp.Custom.Logger.context(meta)
      """
      |> module()
      |> run(extra_loggers: [MyApp.Custom.Logger], extra_logger_functions: [context: 1])
      |> refute_issues()
    end

    test "a wrapper with the same name inside a defimpl" do
      ~S"""
      defmodule CredoSampleModule do
        defimpl CredoSample.Proto do
          require Logger

          def send(msg), do: Logger.info(msg)
        end

        def run(x), do: send(inspect(x))

        defp send(_x), do: :ok
      end
      """
      |> run()
      |> refute_issues()
    end

    test "an alias declared in a defimpl" do
      ~S"""
      defmodule CredoSampleModule do
        defimpl CredoSample.Proto, for: CredoSample.Type do
          alias Logger, as: L
        end

        def run(x), do: L.error("a #{inspect(x)}")
      end
      """
      |> run()
      |> refute_issues()
    end

    test "an import declared in a defimpl" do
      ~S"""
      defmodule CredoSampleModule do
        defimpl CredoSample.Proto, for: CredoSample.Type do
          import Logger
        end

        def run(x), do: error("a #{inspect(x)}")
      end
      """
      |> run()
      |> refute_issues()
    end

    test "an unconfigured module required as Logger" do
      ~S"""
      defmodule CredoSampleModule do
        require My.Custom.Logger, as: Logger

        def run(x), do: Logger.error("a #{inspect(x)}")
      end
      """
      |> run()
      |> refute_issues()
    end

    test "an alias declared in an earlier sibling module" do
      ~S"""
      defmodule CredoSampleModule.A do
        alias Logger, as: L
      end

      defmodule CredoSampleModule.B do
        def run(x), do: L.error("a #{inspect(x)}")
      end
      """
      |> run()
      |> refute_issues()
    end

    test "an import declared in an earlier sibling module" do
      ~S"""
      defmodule CredoSampleModule.A do
        import Logger
      end

      defmodule CredoSampleModule.B do
        def run(x), do: error("a #{inspect(x)}")
      end
      """
      |> run()
      |> refute_issues()
    end

    test "a keyword argument to an extra logger function" do
      ~S|    MyApp.Custom.Logger.context(reason: inspect(x))|
      |> module()
      |> run(extra_loggers: [MyApp.Custom.Logger], extra_logger_functions: [context: 1])
      |> refute_issues()
    end

    for {name, body} <- [
          {"metadata", ~S|    Logger.error("failed", reason: inspect(x))|},
          {"Logger.metadata/1", ~S|    Logger.metadata(reason: inspect(x))|},
          {"a plain term in metadata", ~S|    Logger.error("failed", reason: x)|},
          {"Exception.message/1", ~S|    Logger.error("failed: #{Exception.message(e)}")|},
          {"to_string/1", ~S|    Logger.error("failed: #{to_string(x)}")|},
          {"a variable", ~S|    Logger.error(x)|},
          {"IO.puts/1", ~S|    IO.puts("a #{inspect(x)}")|},
          {"the log level argument", ~S|    Logger.log(inspect(x), "a")|},
          {":logger metadata", ~S|    :logger.error("a", %{reason: inspect(x)})|},
          {"metadata in a lazy message", ~S|    Logger.error(fn -> {"a", reason: inspect(x)} end)|},
          {"an unconfigured logger module", ~S|    MyApp.Custom.Logger.error("a #{inspect(x)}")|},
          {"an unconfigured logger function", ~S|    Logger.oops("a #{inspect(x)}")|}
        ] do
      test name do
        unquote(body)
        |> module()
        |> run()
        |> refute_issues()
      end
    end

    test "an extra logger function with a different arity" do
      ~S|    Logger.oops("a #{inspect(x)}", e: e)|
      |> module()
      |> run(extra_logger_functions: [oops: 1])
      |> refute_issues()
    end

    test "an extra logger function on a module that isn't a logger" do
      ~S|    Other.oops("a #{inspect(x)}")|
      |> module()
      |> run(extra_logger_functions: [oops: 1])
      |> refute_issues()
    end

    test "a variable reassigned to a clean value" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x) do
          msg = "a #{inspect(x)}"
          msg = redact(msg)
          Logger.error(msg)
        end
      end
      """
      |> run()
      |> refute_issues()
    end

    test "a variable assigned after the call" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x, msg) do
          Logger.error(msg)
          msg = "a #{inspect(x)}"
          msg
        end
      end
      """
      |> run()
      |> refute_issues()
    end

    test "an assignment nested in an if block" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x, ok?) do
          msg = "a"

          if ok? do
            msg = "a #{inspect(x)}"
            msg
          end

          Logger.error(msg)
        end
      end
      """
      |> run()
      |> refute_issues()
    end

    test "a variable from another function" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def build(x) do
          msg = "a #{inspect(x)}"
          msg
        end

        def run(msg), do: Logger.error(msg)
      end
      """
      |> run()
      |> refute_issues()
    end

    test "a local function that doesn't log its parameter" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x), do: note(inspect(x))

        defp note(text) do
          Logger.info("noted")
          text
        end
      end
      """
      |> run()
      |> refute_issues()
    end

    test "inside a wrapper's own body" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        defp send_message(level, text), do: Logger.log(level, "[svc] " <> text)
      end
      """
      |> run()
      |> refute_issues()
    end

    test "wrappers nested six deep (discovery stops after five passes)" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x), do: w6("a #{inspect(x)}")

        defp w6(t), do: w5(t)
        defp w5(t), do: w4(t)
        defp w4(t), do: w3(t)
        defp w3(t), do: w2(t)
        defp w2(t), do: w1(t)
        defp w1(t), do: Logger.info(t)
      end
      """
      |> run()
      |> refute_issues()
    end

    test "a variable bound by a case pattern" do
      ~S"""
      defmodule CredoSampleModule do
        require Logger

        def run(x) do
          case x do
            {:ok, msg} -> Logger.error(msg)
          end
        end
      end
      """
      |> run()
      |> refute_issues()
    end

    test "a pipe that doesn't end in inspect" do
      ~S'    Logger.error(x |> to_string())'
      |> module()
      |> run()
      |> refute_issues()
    end

    test "an anonymous function call" do
      ~S'    e.("a #{inspect(x)}")'
      |> module()
      |> run()
      |> refute_issues()
    end

    test "a :logger function that doesn't log" do
      ~S'    :logger.add_primary_filter(:id, {e, inspect(x)})'
      |> module()
      |> run()
      |> refute_issues()
    end

    test "a bare call imported with only: :sigils" do
      ~S"""
      defmodule CredoSampleModule do
        import Logger, only: :sigils

        def run(x), do: error("a #{inspect(x)}")
      end
      """
      |> run()
      |> refute_issues()
    end

    test "a module aliased from __MODULE__ as Logger" do
      ~S"""
      defmodule CredoSampleModule do
        alias __MODULE__.Logger

        def run(x), do: Logger.error("a #{inspect(x)}")
      end
      """
      |> run()
      |> refute_issues()
    end
  end

  # `run_check/3` runs the check in a linked process, so a configuration error is asserted
  # against `LoggerCalls.find/3` directly.
  describe "extra_logger_functions validation" do
    test "rejects a /0 function" do
      assert_raise ArgumentError, ~r/arity >= 1, got: \{:oops, 0\}/, fn ->
        LoggerCalls.find(Code.string_to_quoted!("Logger.oops()"), [], oops: 0)
      end
    end

    test "rejects a bare atom" do
      assert_raise ArgumentError, ~r/\{name, arity\}.*got: :oops/, fn ->
        LoggerCalls.find(Code.string_to_quoted!(~S|Logger.oops("a")|), [], [:oops])
      end
    end

    test "a module aliased as Logger" do
      ~S"""
      defmodule CredoSampleModule do
        alias MyApp.Logger

        def run(x), do: Logger.error("a #{inspect(x)}")
      end
      """
      |> run()
      |> refute_issues()
    end

    test "a bare call excluded by import only:" do
      ~S"""
      defmodule CredoSampleModule do
        import Logger, only: [info: 1]

        def run(x), do: error("a #{inspect(x)}")
      end
      """
      |> run()
      |> refute_issues()
    end

    test "a bare call excluded by import except:" do
      ~S"""
      defmodule CredoSampleModule do
        import Logger, except: [error: 1]

        def run(x), do: error("a #{inspect(x)}")
      end
      """
      |> run()
      |> refute_issues()
    end

    test "a bare call without an import" do
      ~S"""
      defmodule CredoSampleModule do
        def run(x), do: error("a #{inspect(x)}")
        defp error(message), do: message
      end
      """
      |> run()
      |> refute_issues()
    end

    test "a bare call before the import is declared" do
      ~S"""
      defmodule CredoSampleModule do
        def run(x), do: error("a #{inspect(x)}")
        import Logger
      end
      """
      |> run()
      |> refute_issues()
    end
  end
end
