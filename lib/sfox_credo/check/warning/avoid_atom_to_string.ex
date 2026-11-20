# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/sfox_credo/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

# coveralls-ignore-next-line
defmodule SfoxCredo.Check.Warning.AvoidAtomToString do
  @moduledoc """
  This check warns against using `Atom.to_string/1`.

  Passing a non-atom argument to `Atom.to_string/1` raises an ArgumentError; callers
  should prefer `to_string/1`, except in cases where the input is _guaranteed_ to be an
  atom (`Macro.to_string(Atom)` outputs `Atom`; `Atom.to_string(Atom)` outputs
  `Elixir.Atom`). An exception is made for `Atom.to_string(nil)` where the output is
  materially different than `to_string(nil)` (`"nil"` vs `""`).

  Local aliases are resolved prior to the check. `A.to_string` when `alias Atom, as: A`
  has been seen will still be flagged. This means that `alias MyApp.Atom` will not cause
  the aliased `Atom.to_string` to be triggered. Alias resolution is not block scoped, but
  is tracked by declaration position.

  ```elixir
  defmodule Example do
    Atom.to_string(:foo) # matched

    alias Atom, as: A
    A.to_string(:foo) # matched

    def foo do
      alias Example.Atom, as: A
      A.to_string(:foo) # not matched
    end

    A.to_string(:foo) # not matched because of declaration tracking
  end
  ```

  Importing `to_string` from `Atom` will not be detected.

  ```elixir
  defmodule Example do
    def foo do
      import Kernel, except: [to_string: 1]
      import Atom, only: [to_string: 1]
      to_string(:foo) # not matched
    end
  end
  ```
  """

  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    tags: [:correctness],
    explanations: [
      check: """
      Prefer `to_string/1` over `Atom.to_string/1`.
      """
    ]

  alias SfoxCredo.Check.Aliases

  def run(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    ast = SourceFile.ast(source_file)
    collect_issues(ast, issue_meta)
  end

  defp collect_issues(ast, issue_meta) do
    aliases = Aliases.collect(ast)

    {_, issues} =
      Macro.postwalk(ast, [], fn node, acc ->
        case issue_for_node(node, aliases) do
          nil -> {node, acc}
          line -> {node, [line | acc]}
        end
      end)

    Enum.map(issues, fn line ->
      format_issue(
        issue_meta,
        message: "Prefer `to_string/1` over `Atom.to_string/1`.",
        line_no: line
      )
    end)
  end

  defp issue_for_node({{:., _, [module, :to_string]}, meta, args}, aliases) when is_list(args) do
    line = Keyword.get(meta, :line)

    cond do
      args == [] and atom_module?(module, line, aliases) ->
        line

      match?([_], args) and atom_module?(module, line, aliases) and not nil_literal?(hd(args)) ->
        line

      true ->
        nil
    end
  end

  defp issue_for_node(_, _aliases), do: nil

  defp atom_module?(module, line, aliases) do
    Aliases.resolve(module, line, aliases) == {:ok, [:Atom]}
  end

  defp nil_literal?(nil), do: true
  defp nil_literal?(_), do: false
end
