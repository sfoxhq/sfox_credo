# coveralls-ignore-next-line
defmodule SfoxCredo.Check.Warning.AshCallInEnum do
  @moduledoc """
  Checks for `Ash` calls that go to the data layer once for each element of a
  collection.

  The check reads the function given to `Enum.map/2` and `Enum.each/2` (also in a
  pipe and as a `&` capture) and the `do` body of a `for` comprehension:

  ```elixir
  Enum.map(ids, &Ash.get!(Customer, &1))  # matched

  for customer <- customers do
    Ash.load!(customer, :documents)       # matched
  end

  customers = Ash.read!(Customer)         # not matched: one call for the list
  Enum.map(customers, & &1.name)
  ```

  Use one call for the full collection instead, for example a read with a filter,
  `Ash.load/3` on a list, or a bulk action.

  Only calls on the `Ash` module that go to the data layer match, for example
  `Ash.read!/2`, `Ash.get/3`, `Ash.load/3` and `Ash.bulk_create/4`. Calls that only
  build a query or a changeset, such as `Ash.Query.filter/2` or
  `Ash.Changeset.for_create/4`, do not match. Code interface functions on a domain
  do not match, because the check cannot find them by name.

  ### Parameters

  - `include_tests`: Set to `true` to also check files in `test/` directories. The
    default is `false`, because a test often loops over a few cases on purpose.
  """

  # coveralls-ignore-next-line
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [include_tests: false],
    explanations: [
      check: """
      An `Ash` data layer call inside `Enum.map/2`, `Enum.each/2` or a `for` body runs
      once for each element (an N+1 query). Use one call for the full collection: a
      read with a filter, `Ash.load/3` on a list, or a bulk action.
      """,
      params: [
        include_tests: "Set to `true` to also check files in `test/` directories."
      ]
    ]

  @enum_functions [:map, :each]

  @data_layer_functions ~w(
    aggregate aggregate! avg avg! bulk_create bulk_create! bulk_destroy bulk_destroy!
    bulk_update bulk_update! calculate calculate! count count! create create!
    destroy destroy! exists exists? first first! get get! list list! load load!
    max max! min min! page page! read read! read_first read_first! read_one read_one!
    reload reload! run_action run_action! stream! sum sum! transact transaction
    update update! update_many update_many!
  )a

  def run(source_file, params) do
    if Params.get(params, :include_tests, __MODULE__) or not test_file?(source_file.filename) do
      find_issues(source_file, params)
    else
      []
    end
  end

  defp test_file?(filename), do: String.contains?("/" <> filename, "/test/")

  defp find_issues(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> SourceFile.ast()
    |> per_element_bodies()
    |> Enum.flat_map(&ash_calls/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn {line, column, function} ->
      format_issue(
        issue_meta,
        message: "`Ash.#{function}` runs once for each element. Use one call for the full collection.",
        trigger: "Ash.#{function}",
        line_no: line,
        column: column
      )
    end)
  end

  defp per_element_bodies(ast) do
    {_ast, bodies} = Macro.prewalk(ast, [], fn node, acc -> {node, per_element_body(node) ++ acc} end)
    bodies
  end

  defp per_element_body({{:., _, [{:__aliases__, _, [:Enum]}, function]}, _, [_ | _] = args})
       when function in @enum_functions do
    case List.last(args) do
      {:fn, _, _} = fun -> [fun]
      {:&, _, _} = fun -> [fun]
      _ -> []
    end
  end

  defp per_element_body({:for, _, [_ | _] = args}) do
    case List.last(args) do
      options when is_list(options) ->
        options
        |> Keyword.take([:do])
        |> Keyword.values()

      _ ->
        []
    end
  end

  defp per_element_body(_), do: []

  defp ash_calls(body) do
    {_ast, calls} = Macro.prewalk(body, [], fn node, acc -> {node, ash_call(node) ++ acc} end)
    calls
  end

  defp ash_call({{:., _, [{:__aliases__, meta, [:Ash]}, function]}, _, args})
       when function in @data_layer_functions and is_list(args) do
    [{meta[:line], meta[:column], function}]
  end

  defp ash_call(_), do: []
end
