# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/sfox_credo/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

if Code.ensure_loaded?(Ash) do
  # coveralls-ignore-next-line
  defmodule SfoxCredo.Check.Refactor.AshCallInEnum do
    @moduledoc """
    Checks for `Ash` calls that go to the data layer once for each element of
    a collection.

    The check reads every function given to an `Enum` or `Stream` function (also in a pipe
    and as a `&` capture), because each of them calls its function once for each element.
    In a `for` comprehension it reads the `do` body, the filters, and the enumerable
    values of generators after the first, which all run once for each element:

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

    Only calls on the `Ash` module (or an alias of it) that go to the data layer match,
    for example `Ash.read!/2`, `Ash.get/3` and `Ash.load/3`. Calls that only build a query
    or a changeset, such as `Ash.Query.filter/2` or `Ash.Changeset.for_create/4`, do not
    match. Code interface functions on a domain do not match, because the check cannot
    find them by name.

    A call to a function defined in the same module is followed one level: when that
    function calls `Ash` itself, the call in the loop matches.

    ```elixir
    Enum.map(ids, &fetch/1)                 # matched

    defp fetch(id), do: Ash.get!(Customer, id)
    ```

    Batch and bulk operations are not matched:

    - `Ash` bulk actions (`Ash.bulk_create/4`, `Ash.bulk_update/4`, `Ash.bulk_destroy/4`),
      which take a whole batch
    - Loops over `chunk_every`, `chunk_by` or `chunk_while`, which make one call for each
      chunk
    - `Stream.iterate/2`, `Stream.repeatedly/1`, `Stream.resource/3`,
      `Stream.transform/4,5` and `Stream.unfold/2`, which call their functions to produce
      or wrap a stream (reading it a page at a time, for example) rather than once for
      each element of a collection

    ## Parameters

    - `include_tests`: Set to `true` to also check test files: files in the `test/`
      directory of the project or of an umbrella app (`apps/<app>/test/`), and any
      `*_test.exs` file. The default is `false`, because a test often loops over a few
      cases on purpose.

    ## Known gaps

    - `Task.async_stream/3` and other functions outside `Enum` and `Stream` are not read
    - Local functions are followed one level only, and only within the same module.
      A function in another module, or a function given as a variable, is not followed
    - The reducer given to `Stream.transform/4,5` runs once for each element, but is not
      read, along with that function's other functions
    - Code interface functions on a domain or resource do not match
    - Test files are found by path, so a project that sets other `test_paths` in
      `mix.exs` has its test helpers checked (its `*_test.exs` files are still skipped)
    """

    use Credo.Check,
      base_priority: :high,
      category: :refactor,
      tags: [:ash],
      param_defaults: [include_tests: false],
      explanations: [
        check: """
        An `Ash` data layer call inside a function given to `Enum` or `Stream`, or in
        a `for` body or filter, runs once for each element (an N+1 query). Use one call
        for the full collection: a read with a filter, `Ash.load/3` on a list, or a bulk
        action.
        """,
        params: [
          include_tests: """
          Set to `true` to also check test files (in the project's or an umbrella app's
          `test/`, or `*_test.exs`).
          """
        ]
      ]

    alias SfoxCredo.Check.Aliases

    # These call their functions to produce or wrap a stream, not once for each element of
    # a collection, so a call in them can be deliberate paging.
    @stream_exceptions [iterate: 2, repeatedly: 1, resource: 3, transform: 4, transform: 5, unfold: 2]

    @chunk_functions [:chunk_by, :chunk_every, :chunk_while]

    # Bulk actions are left out: they take a whole batch, so calling one per chunk is the
    # batching this check asks for.
    @data_layer_functions ~w(
      aggregate aggregate! avg avg! calculate calculate! count count! create create!
      destroy destroy! exists exists? first first! get get! list list! load load!
      max max! min min! page page! read read! read_first read_first! read_one read_one!
      reload reload! run_action run_action! stream! sum sum! transact transaction
      unpaginated_read unpaginated_read! update update! update_many update_many!
    )a

    @doc false
    # For the test that compares this list with the functions `Ash` exports.
    def data_layer_functions, do: @data_layer_functions

    def run(source_file, params) do
      if Params.get(params, :include_tests, __MODULE__) or not test_file?(source_file.filename) do
        find_issues(source_file, params)
      else
        []
      end
    end

    # A file in the `test/` directory of the project or of an umbrella app, or any
    # `*_test.exs` file. A `test` directory elsewhere (`lib/my_app/test/`, or an umbrella
    # app named `test`) holds application code.
    defp test_file?(filename) do
      path = Path.relative_to_cwd(filename)
      String.ends_with?(path, "_test.exs") or Regex.match?(~r{^(apps/[^/]+/)?test/}, path)
    end

    defp find_issues(source_file, params) do
      issue_meta = IssueMeta.for(source_file, params)
      ast = SourceFile.ast(source_file)
      aliases = Aliases.collect(ast)

      ast
      |> scopes()
      |> Enum.flat_map(&scope_issues(&1, aliases))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn {line, column, trigger, message} ->
        format_issue(issue_meta, message: message, trigger: trigger, line_no: line, column: column)
      end)
    end

    # Each module's body, and the code outside any module, with nested modules cut out, so
    # a loop only follows the local functions of its own module.
    defp scopes(ast) do
      {root, bodies} = cut_modules(ast)
      [root | bodies]
    end

    defp cut_modules(ast) do
      Macro.prewalk(ast, [], fn
        {kind, _, [_ | _] = args} = node, acc when kind in [:defmodule, :defimpl] ->
          case List.last(args) do
            [{:do, body}] ->
              {nested_body, nested} = cut_modules(body)
              {nil, [nested_body | nested] ++ acc}

            # coveralls-ignore-next-line
            _other ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)
    end

    defp scope_issues(scope, aliases) do
      helpers = helpers(scope, aliases)

      scope
      |> loop_bodies(aliases)
      |> Enum.flat_map(&body_issues(&1, helpers, aliases))
    end

    ## Local functions that call `Ash`

    # `{name, arity}` of each local function that calls `Ash` directly, with the first
    # `Ash` function it calls.
    defp helpers(scope, aliases) do
      {_ast, helpers} =
        Macro.prewalk(scope, %{}, fn
          {kind, _, [head, [{:do, body} | _]]} = node, acc when kind in [:def, :defp] ->
            {node, add_helper(acc, head, body, aliases)}

          node, acc ->
            {node, acc}
        end)

      helpers
    end

    defp add_helper(helpers, head, body, aliases) do
      with {name, params} <- definition_head(head),
           [{function, _meta} | _] <- ash_calls(body, aliases) do
        defaults = Enum.count(params, &match?({:\\, _, _}, &1))
        for arity <- (length(params) - defaults)..length(params), into: helpers, do: {{name, arity}, function}
      else
        _ -> helpers
      end
    end

    defp definition_head({:when, _, [head | _guards]}), do: definition_head(head)
    defp definition_head({name, _, params}) when is_atom(name) and is_list(params), do: {name, params}
    defp definition_head({name, _, context}) when is_atom(name) and is_atom(context), do: {name, []}
    # coveralls-ignore-next-line
    defp definition_head(_head), do: nil

    defp ash_calls(body, aliases) do
      {_ast, calls} =
        Macro.prewalk(body, [], fn node, acc ->
          node = unpipe(node)
          {node, List.wrap(ash_call(node, aliases)) ++ acc}
        end)

      # Source order; a prewalk reaches the outer call of a pipe first.
      Enum.sort_by(calls, fn {_function, meta} -> {meta[:line], meta[:column]} end)
    end

    ## Loops

    # The functions and `for` clauses and bodies that run once for each element.
    defp loop_bodies(scope, aliases) do
      {_ast, bodies} =
        Macro.prewalk(scope, [], fn node, acc ->
          node = unpipe(node)
          {node, loop_body(node, aliases) ++ acc}
        end)

      bodies
    end

    defp loop_body({{:., _, [module, function]}, _, [enumerable | _] = args}, aliases) when is_atom(function) do
      if per_element?(module, {function, length(args)}, aliases) and not chunked?(enumerable, aliases) do
        Enum.filter(args, &function_arg?/1)
      else
        []
      end
    end

    defp loop_body({:for, _, [_ | _] = args}, aliases) do
      {clauses, options} = Enum.split_with(args, &(not Keyword.keyword?(&1)))

      if Enum.any?(clauses, &chunked_generator?(&1, aliases)) do
        []
      else
        # Only the first generator's enumerable runs once. Every later clause (a filter,
        # or a later generator's enumerable) runs once for each element, like the body.
        body =
          options
          |> List.flatten()
          |> Keyword.take([:do])
          |> Keyword.values()

        Enum.drop(clauses, 1) ++ body
      end
    end

    defp loop_body(_node, _aliases), do: []

    defp per_element?(module, function_arity, aliases) do
      case resolve(module, aliases) do
        [:Enum] -> true
        [:Stream] -> function_arity not in @stream_exceptions
        _other -> false
      end
    end

    defp function_arg?({:fn, _, _}), do: true
    defp function_arg?({:&, _, _}), do: true
    defp function_arg?(_arg), do: false

    defp chunked_generator?({:<-, _, [_pattern, enumerable]}, aliases), do: chunked?(enumerable, aliases)
    defp chunked_generator?(_clause, _aliases), do: false

    # A loop over chunks makes one call for each chunk, which is batching.
    defp chunked?(enumerable, aliases) do
      case unpipe(enumerable) do
        {{:., _, [module, function]}, _, _} when function in @chunk_functions ->
          resolve(module, aliases) in [[:Enum], [:Stream]]

        _other ->
          false
      end
    end

    ## Calls in a loop

    defp body_issues(body, helpers, aliases) do
      {_ast, issues} =
        Macro.prewalk(body, [], fn node, acc ->
          node = unpipe(node)
          {node, call_issues(node, helpers, aliases) ++ acc}
        end)

      issues
    end

    defp call_issues({{:., _, [_module, _function]}, _, _args} = node, _helpers, aliases) do
      case ash_call(node, aliases) do
        {function, meta} ->
          [
            {meta[:line], meta[:column], "Ash.#{function}",
             "`Ash.#{function}` runs once for each element. Use one call for the full collection."}
          ]

        nil ->
          []
      end
    end

    # A captured local function, `&fetch/1`.
    defp call_issues({:&, _, [{:/, _, [{name, meta, context}, arity]}]}, helpers, _aliases)
         when is_atom(name) and is_atom(context) and is_integer(arity) do
      helper_issues(name, arity, meta, helpers)
    end

    defp call_issues({name, meta, args}, helpers, _aliases) when is_atom(name) and is_list(args) do
      helper_issues(name, length(args), meta, helpers)
    end

    defp call_issues(_node, _helpers, _aliases), do: []

    defp helper_issues(name, arity, meta, helpers) do
      case Map.fetch(helpers, {name, arity}) do
        {:ok, function} ->
          [
            {meta[:line], meta[:column], "#{name}/#{arity}",
             "`#{name}/#{arity}` calls `Ash.#{function}`, which runs once for each element. " <>
               "Use one call for the full collection."}
          ]

        :error ->
          []
      end
    end

    ## Shared

    defp ash_call({{:., _, [{:__aliases__, meta, _} = module, function]}, _, args}, aliases)
         when function in @data_layer_functions and is_list(args) do
      if resolve(module, aliases) == [:Ash] do
        {function, meta}
      end
    end

    defp ash_call(_node, _aliases), do: nil

    defp resolve({:__aliases__, meta, _} = module, aliases) do
      case Aliases.resolve(module, Keyword.get(meta, :line, 0), aliases) do
        {:ok, segments} -> segments
        :error -> nil
      end
    end

    defp resolve(_module, _aliases), do: nil

    # `lhs |> f(args)` as `f(lhs, args)`, so a piped call has its full argument list.
    defp unpipe({:|>, _, [lhs, {callee, meta, args}]}) when is_list(args), do: {callee, meta, [lhs | args]}
    defp unpipe(node), do: node
  end
end
