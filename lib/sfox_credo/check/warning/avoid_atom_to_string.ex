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
    explanations: [
      check: """
      Prefer `to_string/1` over `Atom.to_string/1`.
      """
    ]

  def run(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    ast = SourceFile.ast(source_file)
    collect_issues(ast, issue_meta)
  end

  defp collect_issues(ast, issue_meta) do
    aliases = collect_aliases(ast)

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

  defp atom_module?({:__aliases__, _, [name]}, line, aliases) do
    case resolve_alias(name, line, aliases) do
      {:ok, canonical} -> real_atom_module?(canonical)
      :error -> name == :Atom
    end
  end

  defp atom_module?(_, _line, _aliases), do: false

  defp real_atom_module?([:Atom]), do: true
  defp real_atom_module?([Elixir, :Atom]), do: true
  defp real_atom_module?(_), do: false

  defp resolve_alias(name, line, aliases) do
    case matching_aliases(name, line, aliases) do
      [] ->
        :error

      matches ->
        {:ok,
         matches
         |> Enum.max_by(&elem(&1, 0))
         |> elem(2)}
    end
  end

  defp matching_aliases(name, line, aliases) do
    Enum.filter(aliases, fn {alias_line, alias_name, _canonical} -> alias_name == name and alias_line <= line end)
  end

  defp nil_literal?(nil), do: true
  defp nil_literal?(_), do: false

  # Approximates Elixir's alias scoping by tracking declaration line rather than lexical
  # block — see the moduledoc.
  defp collect_aliases(ast) do
    {_, aliases} = Macro.postwalk(ast, [], &collect_alias_node/2)
    aliases
  end

  defp collect_alias_node({:alias, meta, [{:__aliases__, _, segments}]} = node, acc) do
    {node, [alias_entry(meta, segments, List.last(segments)) | acc]}
  end

  defp collect_alias_node({:alias, meta, [{:__aliases__, _, segments}, opts]} = node, acc) when is_list(opts) do
    entry =
      case Keyword.get(opts, :as) do
        {:__aliases__, _, as_segments} -> alias_entry(meta, segments, List.last(as_segments))
        _ -> alias_entry(meta, segments, List.last(segments))
      end

    {node, [entry | acc]}
  end

  defp collect_alias_node({:alias, meta, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, items}]} = node, acc) do
    entries =
      Enum.map(items, fn {:__aliases__, _, tail} ->
        full = base ++ tail
        alias_entry(meta, full, List.last(full))
      end)

    {node, entries ++ acc}
  end

  defp collect_alias_node(node, acc), do: {node, acc}

  defp alias_entry(meta, canonical_segments, local_name) do
    {Keyword.get(meta, :line, 0), local_name, canonical_segments}
  end
end
