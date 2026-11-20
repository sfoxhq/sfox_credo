# coveralls-ignore-next-line
defmodule SfoxCredo.Check.Warning.LoggerMetadataInspect do
  @moduledoc ~S"""
  This check warns against `inspect/1,2` in a metadata value of a Logger call.

  `inspect/1` flattens a term into Elixir syntax. As a metadata value, that string may
  carry every field of the term, including ones that hold personal data, and it hides the
  structure a log formatter could otherwise keep. Pass the term itself, or exempt the line
  with a `# credo:disable-for-next-line` comment when the inspected string is intentional.

  The metadata argument of a Logger call, the argument to `Logger.metadata/1` and
  `Logger.reset_metadata/1`, and the metadata half of a lazy message's
  `{message, metadata}` result are checked. Metadata is a `{key, value}` enumerable, so
  keyword lists and map literals both count, as do their combinations through `++`,
  `Keyword.merge/2`, `Keyword.put/3`, `Keyword.put_new/3`, `Map.merge/2`, `Map.put/3`, and
  `Map.put_new/3`. A value matches when `inspect/1` appears in it directly, through
  interpolation, `<>`, a pipe, a conditional branch, or a nested keyword list, map,
  struct, or tuple:

  ```elixir
  Logger.error("failed", reason: inspect(reason))          # matched
  Logger.error("failed", reason: "got #{inspect(reason)}") # matched
  Logger.error("failed", error: {:error, inspect(reason)}) # matched
  Logger.error("failed", Keyword.put(meta, :reason, inspect(reason))) # matched
  Logger.metadata(%{reason: inspect(reason)})              # matched
  Logger.error(fn -> {"failed", reason: inspect(reason)} end) # matched
  :logger.error("failed", %{reason: inspect(reason)})      # matched

  Logger.error("failed", reason: reason)                   # not matched
  Logger.error("failed: #{inspect(reason)}")               # not matched (message, not metadata)
  ```

  Calls to `Logger` (or `Elixir.Logger`) are always checked: the level functions
  (including the deprecated `warn`), `log/3`, `bare_log/3`, `metadata/1`,
  `reset_metadata/1`, calls through
  `require Logger, as: L` or `alias Logger, as: L`, and bare calls after `import Logger`
  (respecting `only:` and `except:`). Erlang `:logger` level functions, `:logger.log`,
  `:logger.set_process_metadata/1` and `:logger.update_process_metadata/1` are checked too.

  `inspect/1` in the message is reported by
  `SfoxCredo.Check.Warning.LoggerMessageInspect`, not this check.

  ## Parameters

  - `allowed_keys`: metadata keys whose value may be an `inspect`ed string, such as
    `[:query]`. Atom and string keys with the same name match each other. Use this with
    caution.

  - `extra_loggers`: additional logger modules, such as `[MyApp.Custom.Logger]`, checked
    like `Logger`.

  - `extra_logger_functions`: more functions on the logger modules, as a `[name: arity]`
    keyword list, such as `[context: 1]`. Arity must be at least 1. This allows a custom
    function on a module that wraps `Logger`, such as a `context/1` with this and
    `extra_loggers` combined:

    ```elixir
    {SfoxCredo.Check.Warning.LoggerMetadataInspect, [
      extra_loggers: [MyApp.Custom.Logger],
      extra_logger_functions: [context: 1]
    ]}
    ```

    This will match `MyApp.Custom.Logger.context(reason: inspect(r))`. Bare calls after
    `import Logger` never match these, since `import Logger` imports only `Logger`'s own
    functions.

  Metadata is also followed through variables and local wrappers:

  ```elixir
  meta = [reason: inspect(reason)]     # matched, on this line
  Logger.error("failed", meta)

  defp log_failure(reason), do: Logger.error("failed", reason: reason)
  log_failure(inspect(reason))         # matched
  ```

  A variable is followed when it is assigned by a `var = expr` statement written directly
  in a function body or clause body; the last such assignment before the Logger call
  wins. A `def` or `defp` that passes one of its parameters into a Logger call's message
  or metadata is treated as a logger function for calls in the same module, including
  wrappers of wrappers. An Erlang `:logger` call's second argument is metadata when it is
  a map (a literal, a `Map.merge/2`, `Map.put/3` or `Map.put_new/3` result, or a variable
  assigned one); otherwise it is the format argument list.

  ## Known gaps

  - Metadata built and returned by another function (other than the `Keyword` and `Map`
    functions above) is not followed, nor are assignments inside `if`, `case`, or other
    nested blocks, pattern-match bindings (which do clear an earlier assignment), or module
    attributes.
  - A locally defined or imported `inspect/1` is treated as `Kernel.inspect/1`.
  - Wrappers are found only for local (bare) calls in the defining file; a wrapper in
    another module needs `extra_loggers` and `extra_logger_functions`.
  - Wrappers of wrappers are followed up to five levels deep.
  - Aliases and imports are scoped to their enclosing `defmodule`, not to narrower blocks:
    one declared inside a function or `if` applies until the end of the module.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [allowed_keys: [], extra_loggers: [], extra_logger_functions: []],
    explanations: [
      check: """
      Don't use `inspect/1` in log metadata. It flattens terms (and any personal data they
      hold) into a string. Pass the term, or exempt the line.
      """,
      params: [
        allowed_keys: "Metadata keys whose value may be an `inspect`ed string.",
        extra_loggers: "Additional logger modules to check, such as `[MyApp.Custom.Logger]`.",
        extra_logger_functions:
          "Additional functions on logger modules, as a `[name: arity]` keyword list (arity >= 1)."
      ]
    ]

  alias SfoxCredo.Check.LoggerCalls

  @message "Don't use `inspect/1` in log metadata; pass the term, or exempt the line."

  def run(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    # Metadata keys may be atoms or strings; `:query` and `"query"` are the same key.
    allowed_keys =
      params
      |> Params.get(:allowed_keys, __MODULE__)
      |> Enum.map(&to_string/1)

    extra_loggers = Params.get(params, :extra_loggers, __MODULE__)
    extra_functions = Params.get(params, :extra_logger_functions, __MODULE__)

    source_file
    |> SourceFile.ast()
    |> LoggerCalls.find(extra_loggers, extra_functions)
    |> Enum.flat_map(fn call ->
      for {key, lines} <- call.metadata, to_string(key) not in allowed_keys, line <- lines, do: {key, line}
    end)
    # One `inspect` assigned to a variable can reach several Logger calls; report it once.
    |> Enum.uniq()
    |> Enum.map(fn {key, line} ->
      format_issue(issue_meta, message: @message, trigger: to_string(key), line_no: line)
    end)
  end
end
