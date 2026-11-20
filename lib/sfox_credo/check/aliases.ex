# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/sfox_credo/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule SfoxCredo.Check.Aliases do
  @moduledoc false

  # This approximates Elixir's lexical alias scoping by line ranges: an alias applies from
  # its declaration line to the end of the enclosing `defmodule`, even when it is declared
  # inside a narrower block such as a `def` or `if`. Checks that use this document the
  # approximation in their moduledocs.

  @type scope_end :: non_neg_integer() | :infinity
  @type entry ::
          {line :: non_neg_integer(), scope_end(), local_name :: atom(), canonical :: [atom() | Macro.t()]}
  @type t :: [entry()]

  @doc false
  @spec collect(Macro.t()) :: t()
  def collect(ast) do
    {_, {aliases, _modules}} = Macro.traverse(ast, {[], []}, &enter/2, &leave/2)
    aliases
  end

  @doc false
  # The last line of a `defmodule`, from the `end` metadata Credo's parser provides. A
  # `do:` one-liner has none, so its scope never ends. (Any integer sorts before an atom,
  # so `line <= :infinity` always holds.)
  @spec scope_end(Keyword.t()) :: scope_end()
  def scope_end(meta), do: get_in(meta, [:end, :line]) || :infinity

  @doc false
  # Whether `line` falls in the scope of a declaration made on `from` that lasts to `to`.
  @spec in_scope?(non_neg_integer(), non_neg_integer(), scope_end()) :: boolean()
  def in_scope?(line, from, to), do: from <= line and line <= to

  # Nested `defmodule` names and end lines are tracked on a stack: `defmodule Logger`
  # inside `defmodule MyApp` defines `MyApp.Logger` and aliases `Logger` to it until the
  # end of `MyApp`.
  defp enter({:defmodule, meta, [name, _body]} = node, {acc, modules}) do
    segments = module_segments(name)
    module = {module_name(segments, modules), scope_end(meta)}
    {node, {nested_alias(acc, meta, segments, modules), [module | modules]}}
  end

  # `defimpl` defines a module too, so it scopes its aliases, but defines no alias in its
  # parent; nested names under it are approximated by its protocol's name.
  defp enter({:defimpl, meta, [protocol | _]} = node, {acc, modules}) do
    module = {module_name(module_segments(protocol), modules), scope_end(meta)}
    {node, {acc, [module | modules]}}
  end

  defp enter(node, {acc, modules}) do
    {node, acc} = collect_node(node, acc, enclosing_end(modules))
    {node, {acc, modules}}
  end

  defp leave(node, {acc, modules} = state) do
    if module_scope?(node) do
      {node, {acc, tl(modules)}}
    else
      {node, state}
    end
  end

  @doc false
  # Whether a node defines a module (`defmodule` or `defimpl`), and so a scope for aliases
  # and imports.
  @spec module_scope?(Macro.t()) :: boolean()
  def module_scope?({:defmodule, _, [_name, _body]}), do: true
  def module_scope?({:defimpl, _, [_protocol | _]}), do: true
  def module_scope?(_node), do: false

  # A module named by an atom (`defmodule :name`) still scopes its aliases, but defines
  # no alias in its parent.
  defp module_segments({:__aliases__, _, segments}), do: segments
  defp module_segments(name), do: [Elixir, name]

  defp enclosing_end([]), do: :infinity
  defp enclosing_end([{_name, scope_end} | _]), do: scope_end

  defp module_name([Elixir | rest], _modules), do: rest
  defp module_name(segments, []), do: segments
  defp module_name(segments, [{parent, _end} | _]), do: parent ++ segments

  defp nested_alias(acc, meta, [first | _], [{parent, scope_end} | _]) when is_atom(first) and first != Elixir do
    [{Keyword.get(meta, :line, 0), scope_end, first, parent ++ [first]} | acc]
  end

  defp nested_alias(acc, _meta, _segments, _modules), do: acc

  @doc false
  # Resolves a module reference to its canonical segments, without a leading `Elixir`.
  # `{:__aliases__, _, [:L, :Sub]}` with `alias Logger, as: L` becomes `[:Logger, :Sub]`.
  # Returns `:error` for anything that is not a static module reference.
  @spec resolve(Macro.t(), non_neg_integer(), t()) :: {:ok, [atom() | Macro.t()]} | :error
  def resolve({:__aliases__, _, [Elixir | rest]}, _line, _aliases) do
    static_segments(rest)
  end

  def resolve({:__aliases__, _, [first | rest]}, line, aliases) when is_atom(first) do
    with {:ok, rest} <- static_segments(rest) do
      case lookup(first, line, aliases) do
        {:ok, canonical} -> {:ok, canonical ++ rest}
        :error -> {:ok, [first | rest]}
      end
    end
  end

  def resolve(_module, _line, _aliases), do: :error

  @doc false
  # The dotted name of resolved segments (`[:Myapp, :Custom, :Logger]` → `"MyApp.Custom.Logger"`),
  # comparable with `inspect/1` of a configured module without creating atoms.
  @spec name([atom() | Macro.t()]) :: String.t()
  def name(segments), do: Enum.map_join(segments, ".", &segment_name/1)

  defp segment_name(segment) when is_atom(segment), do: to_string(segment)
  defp segment_name(segment), do: Macro.to_string(segment)

  defp lookup(name, line, aliases) do
    matches =
      Enum.filter(aliases, fn {from, to, alias_name, _canonical} -> alias_name == name and in_scope?(line, from, to) end)

    case matches do
      [] ->
        :error

      matches ->
        {:ok,
         matches
         |> Enum.max_by(&elem(&1, 0))
         |> elem(3)}
    end
  end

  defp static_segments(segments) do
    if Enum.all?(segments, &is_atom/1) do
      {:ok, segments}
    else
      :error
    end
  end

  defp collect_node({:alias, meta, [{:__aliases__, _, segments}]} = node, acc, scope_end) do
    {node, add_entry(acc, meta, scope_end, segments, List.last(segments))}
  end

  defp collect_node({:alias, meta, [{:__aliases__, _, segments}, opts]} = node, acc, scope_end) when is_list(opts) do
    local_name =
      case Keyword.get(opts, :as) do
        {:__aliases__, _, as_segments} -> List.last(as_segments)
        _ -> List.last(segments)
      end

    {node, add_entry(acc, meta, scope_end, segments, local_name)}
  end

  defp collect_node({:alias, meta, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, items}]} = node, acc, scope_end) do
    acc =
      Enum.reduce(items, acc, fn
        {:__aliases__, _, tail}, acc ->
          full = base ++ tail
          add_entry(acc, meta, scope_end, full, List.last(full))

        _item, acc ->
          # coveralls-ignore-next-line
          acc
      end)

    {node, acc}
  end

  # `require Logger, as: L` defines an alias; a plain `require` does not.
  defp collect_node({:require, meta, [{:__aliases__, _, segments}, opts]} = node, acc, scope_end) when is_list(opts) do
    case Keyword.get(opts, :as) do
      {:__aliases__, _, as_segments} -> {node, add_entry(acc, meta, scope_end, segments, List.last(as_segments))}
      _ -> {node, acc}
    end
  end

  defp collect_node(node, acc, _scope_end), do: {node, acc}

  # An alias target is itself expanded through earlier aliases, as Elixir does:
  # `alias MyApp.Custom` then `alias Custom.Logger` aliases `MyApp.Custom.Logger`.
  defp add_entry(acc, meta, scope_end, segments, local_name) do
    line = Keyword.get(meta, :line, 0)

    canonical =
      case segments do
        [Elixir | rest] ->
          rest

        [first | rest] when is_atom(first) ->
          case lookup(first, line, acc) do
            {:ok, expanded} -> expanded ++ rest
            :error -> segments
          end

        segments ->
          segments
      end

    # Canonical segments may hold non-atoms (`alias __MODULE__.Atom`). They are kept so
    # the local name still shadows the global module; they just never equal a static
    # module name.
    if is_atom(local_name) do
      [{line, scope_end, local_name, canonical} | acc]
    else
      # coveralls-ignore-next-line
      acc
    end
  end
end
