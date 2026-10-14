# coveralls-ignore-next-line
defmodule SfoxCredo.Check.Design.EctoMigrationTimestamps do
  @moduledoc """
  Checks that Ecto migration `create table` blocks define both `inserted_at` and
  `updated_at` columns.

  ### Parameters

  - `start_after`: The string timestamp (`"20240314000000"`) that marks the earliest
    migration to check. If omitted or nil, all migrations are checked.

  - `inserted_at` / `updated_at`: Alternate names for `inserted_at` and `updated_at`
    columns, respectively. This _only_ applies for explicit column additions (`add
    :created_at, :utc_datetime`) because the `timestamps()` call allows explicit
    overrides. `:inserted_at` and `:updated_at` are always implicitly supported.
  """

  # coveralls-ignore-next-line
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [inserted_at: [], start_after: nil, updated_at: []],
    explanations: [
      check: """
      Checks if database migrations create tables without both inserted_at and
      updated_at columns.
      """,
      params: [
        inserted_at: "A list of names that can be used instead of :inserted_at for manual column creation.",
        start_after:
          "The timestamp that represents the earliest migration to be checked. If not specified, all migrations are checked.",
        updated_at: "A list of names that can be used instead of :updated_at for manual column creation."
      ]
    ]

  def run(source_file, params) do
    if relevant_file?(source_file.filename, Params.get(params, :start_after, __MODULE__)) do
      detect_missing_timestamps(source_file, params)
    else
      []
    end
  end

  defp detect_missing_timestamps(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    ast = SourceFile.ast(source_file)
    inserted_aliases = Params.get(params, :inserted_at, __MODULE__)
    updated_aliases = Params.get(params, :updated_at, __MODULE__)

    missing_timestamps = detect_missing_timestamps_in_ast(ast, inserted_aliases, updated_aliases)

    Enum.map(missing_timestamps, fn {table_name, line, reason} ->
      build_issue(table_name, line, reason, issue_meta, inserted_aliases, updated_aliases)
    end)
  end

  defp detect_missing_timestamps_in_ast(ast, inserted_aliases, updated_aliases) do
    {_ast, issues} =
      Macro.postwalk(ast, [], fn code_part, acc ->
        new_issues = detect_table_creation_without_timestamps(code_part, inserted_aliases, updated_aliases)
        {code_part, acc ++ new_issues}
      end)

    issues
  end

  defp detect_table_creation_without_timestamps(
         {:create, location, [{:table, _, [table_name | _]}, table_body]},
         inserted_aliases,
         updated_aliases
       ) do
    line = Keyword.get(location, :line)

    case check_timestamps_in_table_body(table_body, inserted_aliases, updated_aliases) do
      :ok -> []
      {:error, reason} -> [{table_name, line, reason}]
    end
  end

  defp detect_table_creation_without_timestamps(_, _, _), do: []

  defp check_timestamps_in_table_body([do: block], inserted_aliases, updated_aliases) do
    check_timestamps_in_block(block, inserted_aliases, updated_aliases)
  end

  defp check_timestamps_in_block({:__block__, _, expressions}, inserted_aliases, updated_aliases) do
    check_timestamps(expressions, inserted_aliases, updated_aliases)
  end

  defp check_timestamps_in_block(expression, inserted_aliases, updated_aliases) do
    check_timestamps([expression], inserted_aliases, updated_aliases)
  end

  defp check_timestamps(expressions, inserted_aliases, updated_aliases) do
    {has_timestamps_inserted_at, has_timestamps_updated_at} =
      Enum.find_value(expressions, {false, false}, &timestamps_call/1)

    has_inserted_at = Enum.any?(expressions, &has_inserted_at_column?(&1, inserted_aliases))
    has_updated_at = Enum.any?(expressions, &has_updated_at_column?(&1, updated_aliases))

    inserted_at = has_timestamps_inserted_at || has_inserted_at
    updated_at = has_timestamps_updated_at || has_updated_at

    cond do
      inserted_at and updated_at -> :ok
      inserted_at -> {:error, :updated_at}
      updated_at -> {:error, :inserted_at}
      true -> {:error, :both}
    end
  end

  defp timestamps_call({:timestamps, _, []}), do: {true, true}

  defp timestamps_call({:timestamps, _, [options]}) when is_list(options) do
    {Keyword.get(options, :inserted_at) != false, Keyword.get(options, :updated_at) != false}
  end

  defp timestamps_call(_), do: nil

  defp has_inserted_at_column?({:add, _, [:inserted_at, _ | _]}, _), do: true
  defp has_inserted_at_column?({:add, _, [_ | _]}, []), do: false
  defp has_inserted_at_column?({:add, _, [name, _ | _]}, aliases), do: name in aliases
  defp has_inserted_at_column?(_, _), do: false

  defp has_updated_at_column?({:add, _, [:updated_at, _ | _]}, _), do: true
  defp has_updated_at_column?({:add, _, [_ | _]}, []), do: false
  defp has_updated_at_column?({:add, _, [name, _ | _]}, aliases), do: name in aliases
  defp has_updated_at_column?(_, _), do: false

  defp build_issue(table_name, line, reason, issue_meta, inserted_aliases, updated_aliases) do
    suffix = suffix_message(reason)
    reason = missing_column(reason, inserted_aliases, updated_aliases)

    format_issue(
      issue_meta,
      message: "Table #{table_name} is missing #{reason}. #{suffix}",
      line_no: line
    )
  end

  defp suffix_message(:both) do
    "Use timestamps() or explicit add :inserted_at and add :updated_at columns."
  end

  defp suffix_message(_) do
    "Both inserted_at and updated_at are required."
  end

  defp missing_column(:both, inserted_aliases, updated_aliases) do
    inserted_at = column_message(:inserted_at, inserted_aliases)
    updated_at = column_message(:updated_at, updated_aliases)
    "both #{inserted_at} and #{updated_at} columns"
  end

  defp missing_column(:inserted_at, inserted_aliases, _) do
    inserted_at = column_message(:inserted_at, inserted_aliases)
    "#{inserted_at} column"
  end

  defp missing_column(:updated_at, _, updated_aliases) do
    updated_at = column_message(:updated_at, updated_aliases)
    "#{updated_at} column"
  end

  defp column_message(column, []), do: "#{column}"
  defp column_message(column, aliases), do: "#{column} (or aliases #{Enum.join(aliases, ", ")})"

  defp relevant_file?(path, start_after) do
    !String.starts_with?(path, ["deps/", "_build/"]) &&
      !String.contains?(path, ["/deps/", "/_build/"]) &&
      String.contains?(path, "migrations/") &&
      (start_after == nil || migration_timestamp(path) > start_after)
  end

  defp migration_timestamp(path) do
    path
    |> Path.basename()
    |> String.split("_")
    |> hd()
  end
end
