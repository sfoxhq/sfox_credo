# coveralls-ignore-next-line
defmodule SfoxCredo.Check.Warning.LoggerMessageInspect do
  @moduledoc ~S"""
  This check warns against `inspect/1,2` in the message of a Logger call.

  `inspect/1,2` flattens a term into Elixir syntax. In a log message, that string may
  carry every field of the term, including ones that hold personal data, and a structured
  log collector can only substring-search it. Log the value as metadata or exempt the line
  with a `# credo:disable-for-next-line` comment when the inspected string is intentional.

  Calls to `inspect/1,2` in a log message will be reported in interpolation (including
  lowercase sigils such as `~s`), `<>`, chardata lists, pipes, lazy `fn -> ... end`
  messages, the branches of `if`, `unless`, `case` and `cond` expressions, and the values
  of a report (a keyword list or map, including nested keyword lists, maps, structs, and
  tuples) passed as the message:

  ```elixir
  Logger.error("failed: #{inspect(reason)}")              # matched
  Logger.error("failed: " <> inspect(reason))             # matched
  Logger.error(["failed: ", inspect(reason)])             # matched
  Logger.warning(fn -> "failed: #{inspect(reason)}" end)  # matched
  "failed: #{inspect(reason)}" |> Logger.error()          # matched
  Logger.log(:info, inspect(reason))                      # matched
  :logger.error("failed: ~s", [inspect(reason)])          # matched
  Logger.error(event: :failed, reason: inspect(reason))   # matched
  Logger.error(if ok, do: "done", else: inspect(reason))  # matched

  Logger.error("failed", reason: reason)                  # not matched
  Logger.error("failed: #{Exception.message(e)}")         # not matched
  ```

  Calls to `Logger` (or `Elixir.Logger`) are always checked: the level functions
  (including the deprecated `warn`), `log/2,3`, `bare_log/2,3`, calls through
  `require Logger, as: L` or `alias Logger, as: L`, and bare calls after `import Logger`
  (respecting `only:` and `except:`). Erlang `:logger` level functions and `:logger.log`
  are also checked; their format arguments and report map values are part of the message.

  The `~p`, `~P`, `~w` and `~W` control sequences (with any width, precision, padding or
  modifiers, such as `~tp` or `~10.2p`) in an Erlang `:logger` format string flatten their
  argument just as `inspect/1` does, so they are reported too. Only a literal format
  string is scanned (a string, interpolated string, `~s` or `~c` sigil, or charlist).
  `Logger` messages aren't format strings, so this applies to `:logger` calls only:

  ```elixir
  :logger.error("failed: ~p", [reason])                   # matched
  :logger.error("failed: ~s", [Exception.message(e)])     # not matched
  ```

  `inspect/1` in metadata is reported by `SfoxCredo.Check.Warning.LoggerMetadataInspect`,
  not this check.

  ## Parameters

  - `extra_loggers`: additional logger modules, such as `[MyApp.Custom.Logger]`, checked
    like `Logger`.

  - `extra_logger_functions`: additional functions on the logger modules, as a
    `[name: arity]` keyword list, such as `[notify: 2]`. Arity must be at least 1. Keyword
    list and map arguments (or variables assigned one) are treated as metadata; every
    other argument is part of the message. Bare calls after `import Logger` never match these, since `import Logger`
    imports only `Logger`'s own functions.

  The message is followed through variables and local wrappers:

  ```elixir
  msg = "failed: #{inspect(reason)}"   # matched, on this line
  Logger.error(msg)

  defp send_message(level, text), do: Logger.log(level, "[svc] " <> text)
  send_message(:error, "failed: #{inspect(reason)}") # matched
  ```

  A variable is followed when it is assigned by a `var = expr` statement written
  directly in a function body or clause body; the last such assignment before the
  Logger call wins. A `def` or `defp` that passes one of its parameters into a Logger
  call's message or metadata is treated as a logger function for calls in the same
  module, including wrappers of wrappers.

  ## Known gaps

  - A message built and returned by another function is not followed, nor are assignments
    inside `if`, `case`, or other nested blocks, pattern-match bindings (which do clear an
    earlier assignment), or module attributes.
  - A format string in a variable is not scanned for `~p` and the like.
  - A locally defined or imported `inspect/1` is treated as `Kernel.inspect/1`.
  - Log function wrappers are found only for local calls in the defining file; a wrapper
    in another module needs `extra_loggers` and `extra_logger_functions`.
  - Wrappers of wrappers are followed up to five levels deep.
  - Aliases and imports are scoped to their enclosing `defmodule`, not to narrower blocks:
    one declared inside a function or `if` applies until the end of the module.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [extra_loggers: [], extra_logger_functions: []],
    explanations: [
      check: """
      Don't use `inspect/1` in log messages. It flattens terms (and any personal data they
      hold) into a string. Log the value as metadata, or exempt the line.
      """,
      params: [
        extra_loggers: "Additional logger modules to check, such as `[MyApp.Custom.Logger]`.",
        extra_logger_functions:
          "Additional functions on logger modules, as a `[name: arity]` keyword list (arity >= 1)."
      ]
    ]

  alias SfoxCredo.Check.LoggerCalls

  @message "Don't use `inspect/1` in log messages; log the value as metadata, or exempt the line."
  @format_message "Don't use `~p`/`~w` in :logger formats; they flatten terms like `inspect/1`. Log the value as metadata, or exempt the line."

  def run(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    extra_loggers = Params.get(params, :extra_loggers, __MODULE__)
    extra_functions = Params.get(params, :extra_logger_functions, __MODULE__)

    calls =
      source_file
      |> SourceFile.ast()
      |> LoggerCalls.find(extra_loggers, extra_functions)

    inspects =
      calls
      |> Enum.flat_map(& &1.message)
      # One `inspect` assigned to a variable can reach several Logger calls; report it once.
      |> Enum.uniq()
      |> Enum.map(&{"inspect", &1, @message})

    formats =
      calls
      |> Enum.flat_map(& &1.formats)
      |> Enum.uniq()
      |> Enum.map(fn {directive, line} -> {directive, line, @format_message} end)

    for {trigger, line, message} <- inspects ++ formats do
      format_issue(issue_meta, message: message, trigger: trigger, line_no: line)
    end
  end
end
