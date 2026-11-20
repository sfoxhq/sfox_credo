# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/sfox_credo/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule SfoxCredo.Check.LoggerCalls do
  @moduledoc false

  # Finds Logger calls and reports where `inspect/1,2` results flow into their message and
  # metadata. The checks that use this decide for themselves what to report.
  #
  # Flow is traced through variables assigned by `var = expr` statements written directly
  # in a function body (or a clause body); the last assignment before a use wins, and
  # assignments nested in `if`/`case`/other blocks are not tracked. Pattern bindings (clause
  # heads, `<-` generators) aren't followed but do clear earlier taint. The same tracing
  # finds local wrapper functions: a `def`/`defp` that passes one of its parameters into
  # a Logger call's message or metadata is itself treated as a logger function for calls
  # in the same module.

  alias SfoxCredo.Check.Aliases

  @levels [:emergency, :alert, :critical, :error, :warning, :warn, :notice, :info, :debug]
  @erlang_levels [:emergency, :alert, :critical, :error, :warning, :notice, :info, :debug]
  @erlang_metadata [:set_process_metadata, :update_process_metadata]
  @definitions [:def, :defp]
  @max_wrapper_passes 5

  # `message` holds the lines of `inspect` calls that reach the message; `metadata` holds,
  # per metadata key, the lines of `inspect` calls that reach that key's value. `formats`
  # holds the term-flattening control sequences (`~p` and the like) in an Erlang `:logger`
  # format string, with the line of the call.
  @type call :: %{
          line: non_neg_integer(),
          function: atom(),
          message: [non_neg_integer()],
          metadata: [{atom() | String.t(), [non_neg_integer()]}],
          formats: [{String.t(), non_neg_integer()}]
        }

  @doc false
  # `extra_loggers` is a list of module atoms. `extra_functions` is a `[name: arity]`
  # keyword list of additional functions on logger modules; arity must be at least 1.
  @spec find(Macro.t(), [module()], [{atom(), pos_integer()}]) :: [call()]
  def find(ast, extra_loggers, extra_functions) do
    aliases = Aliases.collect(ast)
    loggers = ["Logger" | Enum.map(extra_loggers, &inspect/1)]

    ctx = %{
      aliases: aliases,
      loggers: loggers,
      functions: Enum.map(extra_functions, &validate_function!/1),
      imports: collect_imports(ast, aliases, loggers),
      defaults: collect_defaults(ast, [], %{}),
      wrappers: %{},
      module: [],
      scope: nil
    }

    ctx = discover_wrappers(ast, ctx, @max_wrapper_passes)

    ast
    |> walk(%{}, ctx, [])
    |> Enum.reverse()
    |> Enum.map(&public_call/1)
  end

  # A `/0` function has no argument to check, so it is a configuration error.
  defp validate_function!({name, arity} = function) when is_atom(name) and is_integer(arity) and arity > 0 do
    function
  end

  defp validate_function!(function) do
    raise ArgumentError,
          "extra_logger_functions entries must be {name, arity} with arity >= 1, got: #{inspect(function)}"
  end

  defp public_call(call) do
    %{
      line: call.line,
      function: call.function,
      message: inspect_lines(call.message, call.line),
      metadata: for({key, origins} <- call.metadata, do: {key, inspect_lines(origins, call.line)}),
      formats: call.formats
    }
  end

  defp inspect_lines(origins, call_line) do
    origins
    |> Enum.flat_map(fn
      # coveralls-ignore-next-line
      {:inspect, 0} -> [call_line]
      {:inspect, line} -> [line]
      _origin -> []
    end)
    |> Enum.uniq()
  end

  ## Wrapper discovery

  # Repeats until no new wrappers turn up, so a wrapper of a wrapper is found too.
  defp discover_wrappers(_ast, ctx, 0), do: ctx

  defp discover_wrappers(ast, ctx, passes) do
    wrappers =
      ast
      |> walk(%{}, ctx, [])
      |> Enum.reduce(%{}, &add_wrapper_roles/2)

    if wrappers == ctx.wrappers do
      ctx
    else
      discover_wrappers(ast, %{ctx | wrappers: wrappers}, passes - 1)
    end
  end

  defp add_wrapper_roles(%{scope: nil}, wrappers), do: wrappers

  # Roles hold parameter indexes; each arity's roles hold that arity's argument positions.
  # A parameter left to its default at some arity has no role there.
  defp add_wrapper_roles(%{scope: {module, name, defaults}} = call, wrappers) do
    roles =
      for({:param, index} <- call.message, do: {:message, index}) ++
        for({key, origins} <- call.metadata, {:param, index} <- origins, do: {:metadata_value, key, index}) ++
        for(index <- call.metadata_params, do: {:metadata, index})

    for {arity, positions} <- arity_positions(defaults), reduce: wrappers do
      wrappers ->
        case Enum.flat_map(roles, &position_role(&1, positions)) do
          [] -> wrappers
          roles -> Map.update(wrappers, {module, name, arity}, Enum.uniq(roles), &Enum.uniq(&1 ++ roles))
        end
    end
  end

  # The parameter index is the last element of every role.
  defp position_role(role, positions) do
    index = tuple_size(role) - 1

    case Map.fetch(positions, elem(role, index)) do
      {:ok, position} -> [put_elem(role, index, position)]
      :error -> []
    end
  end

  ## Walking

  defp walk({kind, _, [head, body]} = node, env, ctx, acc) when kind in @definitions and is_list(body) do
    case definition_head(head) do
      {name, params} ->
        defaults = Map.get(ctx.defaults, {ctx.module, name, length(params)}, default_flags(params))
        scope_ctx = %{ctx | scope: {ctx.module, name, defaults}}

        Enum.reduce(body, acc, fn
          {:do, block}, acc -> walk_block(block, params_env(params), scope_ctx, acc)
          {_key, other}, acc -> walk(other, params_env(params), scope_ctx, acc)
          # coveralls-ignore-next-line
          _other, acc -> acc
        end)

      nil ->
        walk_children(node, env, ctx, acc)
    end
  end

  # A bodiless head only declares defaults (collected beforehand); it calls nothing.
  defp walk({kind, _, [_head]}, _env, _ctx, acc) when kind in @definitions, do: acc

  defp walk({kind, _, _} = node, env, ctx, acc) when kind in [:defmodule, :defimpl] do
    case module_definition(node) do
      {key, body} -> walk(body, %{}, %{ctx | module: ctx.module ++ [key]}, acc)
      # coveralls-ignore-next-line
      nil -> walk_children(node, env, ctx, acc)
    end
  end

  defp walk({:fn, _, clauses}, env, ctx, acc) when is_list(clauses), do: walk_list(clauses, env, ctx, acc)

  # `cond` clause heads are conditions, not patterns: they bind nothing.
  defp walk({:cond, _, [[{:do, clauses}]]}, env, ctx, acc) when is_list(clauses) do
    for {:->, _, [conditions, body]} <- clauses, reduce: acc do
      acc -> walk_block(body, env, ctx, walk_list(conditions, env, ctx, acc))
    end
  end

  # Every clause (`fn`, `case`, `receive`, `rescue`, `with … else`, …) binds its pattern
  # variables, which shadow any earlier taint.
  defp walk({:->, _, [patterns, body]}, env, ctx, acc) when is_list(patterns) do
    walk_block(body, drop_bound(env, clause_patterns(patterns)), ctx, acc)
  end

  # `for` and `with` bind each `<-` pattern for the clauses after it and for the `do` block.
  defp walk({kind, _, [_ | _] = args}, env, ctx, acc) when kind in [:for, :with] do
    {clauses, blocks} = Enum.split_with(args, &(not Keyword.keyword?(&1)))

    {inner, acc} =
      Enum.reduce(clauses, {env, acc}, fn clause, {env, acc} ->
        case generator(clause) do
          {pattern, enum} -> {drop_bound(env, clause_patterns([pattern])), walk(enum, env, ctx, acc)}
          nil -> {bind(clause, env), walk(clause, env, ctx, acc)}
        end
      end)

    Enum.reduce(blocks, acc, fn block, acc ->
      Enum.reduce(block, acc, fn
        {:do, body}, acc -> walk_block(body, inner, ctx, acc)
        {_option, value}, acc -> walk(value, env, ctx, acc)
      end)
    end)
  end

  # A logger call at the end of a pipe is evaluated with the piped value as its first
  # argument.
  defp walk({:|>, _, [lhs, {callee, meta, args}]} = node, env, ctx, acc) when is_list(args) do
    case classify(callee, meta, [lhs | args], env, ctx) do
      nil -> walk_children(node, env, ctx, acc)
      raw -> walk_list([lhs | args], env, ctx, [evaluate(raw, env, ctx) | acc])
    end
  end

  defp walk({callee, meta, args} = node, env, ctx, acc) when is_list(args) do
    case classify(callee, meta, args, env, ctx) do
      nil -> walk_children(node, env, ctx, acc)
      raw -> walk_children(node, env, ctx, [evaluate(raw, env, ctx) | acc])
    end
  end

  defp walk(node, env, ctx, acc), do: walk_children(node, env, ctx, acc)

  defp walk_children({callee, _meta, args}, env, ctx, acc) do
    acc = walk_callee(callee, env, ctx, acc)

    if is_list(args) do
      walk_list(args, env, ctx, acc)
    else
      acc
    end
  end

  defp walk_children({left, right}, env, ctx, acc), do: walk(right, env, ctx, walk(left, env, ctx, acc))
  defp walk_children(list, env, ctx, acc) when is_list(list), do: walk_list(list, env, ctx, acc)
  defp walk_children(_node, _env, _ctx, acc), do: acc

  defp walk_callee(callee, env, ctx, acc) when is_tuple(callee), do: walk(callee, env, ctx, acc)
  defp walk_callee(_callee, _env, _ctx, acc), do: acc

  defp walk_list(list, env, ctx, acc), do: Enum.reduce(list, acc, &walk(&1, env, ctx, &2))

  # Statements of a body run in order; each `var = expr` statement updates the environment
  # for the statements after it.
  defp walk_block(body, env, ctx, acc) do
    {_env, acc} =
      Enum.reduce(statements(body), {env, acc}, fn statement, {env, acc} ->
        {bind(statement, env), walk(statement, env, ctx, acc)}
      end)

    acc
  end

  defp statements({:__block__, _, statements}) when is_list(statements), do: statements
  defp statements(statement), do: [statement]

  ## Variable environment

  defp bind({:=, _, [{var, _, context}, rhs]}, env) when is_atom(var) and is_atom(context) do
    Map.put(env, var, %{origins: origins(rhs, env), pairs: pairs(rhs, env), map: map?(rhs, env)})
  end

  defp bind({:=, _, [pattern, _rhs]}, env), do: drop_bound(env, pattern)
  defp bind(_statement, env), do: env

  # Removes every variable a pattern binds, so a rebinding the tracer doesn't follow
  # clears any earlier taint.
  defp drop_bound(env, pattern) do
    {_, env} =
      Macro.prewalk(pattern, env, fn
        {:^, _, _}, env -> {nil, env}
        {var, _, context} = node, env when is_atom(var) and is_atom(context) -> {node, Map.delete(env, var)}
        node, env -> {node, env}
      end)

    env
  end

  defp params_env(params) do
    params
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {param, index}, env ->
      case param_var(param) do
        nil -> env
        var -> Map.put(env, var, %{origins: [{:param, index}], pairs: nil, map: false})
      end
    end)
  end

  defp param_var({:\\, _, [param, _default]}), do: param_var(param)
  defp param_var({var, _, context}) when is_atom(var) and is_atom(context), do: var
  defp param_var(_param), do: nil

  defp definition_head({:when, _, [head | _guards]}), do: definition_head(head)
  defp definition_head({name, _, params}) when is_atom(name) and is_list(params), do: {name, params}
  defp definition_head({name, _, context}) when is_atom(name) and is_atom(context), do: {name, []}
  defp definition_head(_head), do: nil

  defp default_flags(params), do: Enum.map(params, &match?({:\\, _, _}, &1))

  # A definition with default arguments defines every arity from the required count up.
  # A call with fewer arguments leaves out the rightmost defaulted parameters, so each
  # arity maps the parameters it supplies (by index) to their argument positions.
  defp arity_positions(defaults) do
    defaulted = for {true, index} <- Enum.with_index(defaults), do: index

    for omitted <- 0..length(defaulted)//1 do
      dropped = Enum.take(defaulted, -omitted)
      supplied = for {_default, index} <- Enum.with_index(defaults), index not in dropped, do: index

      {length(supplied),
       supplied
       |> Enum.with_index()
       |> Map.new()}
    end
  end

  # Clause heads may carry a guard; only the patterns bind.
  defp clause_patterns([{:when, _, args}]) when is_list(args), do: Enum.drop(args, -1)
  defp clause_patterns(patterns), do: patterns

  defp generator({:<-, _, [pattern, enum]}), do: {pattern, enum}
  defp generator({:<<>>, _, [{:<-, _, [pattern, enum]}]}), do: {pattern, enum}
  defp generator(_clause), do: nil

  # `defmodule` and `defimpl` both define a module: its identity for scoping wrappers
  # (nested modules extend their parent's) and its body.
  defp module_definition({:defmodule, _, [name, [{:do, body}]]}), do: {module_key(name), body}

  defp module_definition({:defimpl, _, [protocol | rest]}) do
    case rest do
      [opts, [{:do, body}]] when is_list(opts) -> {{:impl, module_key(protocol), module_key(opts[:for])}, body}
      [[{:do, body}]] -> {{:impl, module_key(protocol), nil}, body}
      # coveralls-ignore-next-line
      _ -> nil
    end
  end

  # coveralls-ignore-next-line
  defp module_definition(_node), do: nil

  defp module_key({:__aliases__, _, segments}), do: segments
  defp module_key(name), do: Macro.to_string(name)

  # Default arguments can be declared on a bodiless head, separately from the clauses that
  # use them; these are collected per module before walking.
  defp collect_defaults(ast, module, acc) do
    case ast do
      {kind, _, _} when kind in [:defmodule, :defimpl] ->
        case module_definition(ast) do
          {key, body} -> collect_defaults(body, module ++ [key], acc)
          # coveralls-ignore-next-line
          nil -> acc
        end

      {:__block__, _, statements} when is_list(statements) ->
        Enum.reduce(statements, acc, &collect_defaults(&1, module, &2))

      {kind, _, [head]} when kind in @definitions ->
        with {name, params} <- definition_head(head),
             defaults = default_flags(params),
             true <- Enum.any?(defaults) do
          Map.put(acc, {module, name, length(params)}, defaults)
        else
          _ -> acc
        end

      _other ->
        acc
    end
  end

  ## Origins: where a value's `inspect` calls and parameters come from

  defp origins({:inspect, meta, [_ | _]}, _env), do: [{:inspect, line(meta)}]

  defp origins({{:., _, [{:__aliases__, _, kernel}, :inspect]}, meta, [_ | _]}, _env)
       when kernel in [[:Kernel], [Elixir, :Kernel]] do
    [{:inspect, line(meta)}]
  end

  defp origins({:|>, _, [lhs, rhs]}, env), do: origins(lhs, env) ++ piped_inspect(rhs)
  defp origins({:<<>>, _, parts}, env) when is_list(parts), do: Enum.flat_map(parts, &interpolation_origins(&1, env))
  defp origins({:<>, _, [left, right]}, env), do: origins(left, env) ++ origins(right, env)

  # A lazy message may return `{message, metadata}`; only the message is followed here.
  defp origins({:fn, _, clauses}, env) when is_list(clauses) do
    Enum.flat_map(clauses, fn {:->, _, [args, body]} ->
      {env, value} = block_value(body, drop_bound(env, clause_patterns(args)))
      lazy_message_origins(value, env)
    end)
  end

  defp origins({:__block__, _, _} = block, env), do: block_origins(block, env)

  # The value of a conditional is the value of whichever branch runs.
  defp origins({kind, _, [_ | _] = args}, env) when kind in [:if, :unless, :case, :cond] do
    case List.last(args) do
      [{:do, _} | _] = blocks -> for {_key, body} <- blocks, origin <- branch_origins(kind, body, env), do: origin
      # coveralls-ignore-next-line
      _other -> []
    end
  end

  # A lowercase sigil interpolates like a string (`~s(failed #{inspect(x)})`).
  defp origins({sigil, _, [{:<<>>, _, _} = string, _modifiers]}, env) when is_atom(sigil) do
    case to_string(sigil) do
      "sigil_" <> <<letter, _::binary>> when letter in ?a..?z -> origins(string, env)
      _other -> []
    end
  end

  # Containers (tuples, maps, structs, cons cells) hold their elements' origins, so
  # keyword values, nested maps, and tuples such as `{:error, inspect(e)}` are followed.
  defp origins({:{}, _, elements}, env) when is_list(elements), do: origins(elements, env)
  defp origins({:%{}, _, pairs}, env) when is_list(pairs), do: origins(pairs, env)
  defp origins({:%, _, [_struct, map]}, env), do: origins(map, env)
  defp origins({:|, _, [head, tail]}, env), do: origins(head, env) ++ origins(tail, env)

  defp origins({var, _, context}, env) when is_atom(var) and is_atom(context) do
    case Map.get(env, var) do
      %{origins: origins} -> origins
      nil -> []
    end
  end

  defp origins(list, env) when is_list(list), do: Enum.flat_map(list, &origins(&1, env))
  defp origins({left, right}, env), do: origins(left, env) ++ origins(right, env)
  defp origins(_ast, _env), do: []

  defp lazy_message_origins({message, _metadata}, env), do: origins(message, env)
  defp lazy_message_origins(value, env), do: origins(value, env)

  # `case` binds each clause's pattern; `cond` clause heads are conditions.
  defp branch_origins(kind, clauses, env) when kind in [:case, :cond] and is_list(clauses) do
    Enum.flat_map(clauses, fn {:->, _, [heads, body]} ->
      clause_env =
        if kind == :case do
          drop_bound(env, clause_patterns(heads))
        else
          env
        end

      block_origins(body, clause_env)
    end)
  end

  defp branch_origins(_kind, body, env), do: block_origins(body, env)

  defp block_origins(body, env) do
    {env, value} = block_value(body, env)
    origins(value, env)
  end

  # The value of a block is its last expression, evaluated after the block's assignments.
  defp block_value(body, env) do
    {env, last} =
      Enum.reduce(statements(body), {env, nil}, fn statement, {env, _last} -> {bind(statement, env), statement} end)

    case last do
      {:=, _, [_pattern, rhs]} -> {env, rhs}
      last -> {env, last}
    end
  end

  defp piped_inspect({:inspect, meta, []}), do: [{:inspect, line(meta)}]

  defp piped_inspect({{:., _, [{:__aliases__, _, kernel}, :inspect]}, meta, []})
       when kernel in [[:Kernel], [Elixir, :Kernel]] do
    [{:inspect, line(meta)}]
  end

  defp piped_inspect(_ast), do: []

  defp interpolation_origins({:"::", _, [{{:., _, [_kernel, :to_string]}, _, [expr]}, _type]}, env) do
    origins(expr, env)
  end

  defp interpolation_origins(_part, _env), do: []

  defp line(meta), do: Keyword.get(meta, :line, 0)

  ## Metadata

  # Metadata is a `{key, value}` enumerable, so keyword lists and map literals both count,
  # as do a variable assigned one of them and the results of combining them. Anything else
  # has no pairs to check.
  defp metadata_entries(ast, env), do: pairs(ast, env) || []

  # Whether an argument holds metadata pairs, as opposed to message text.
  defp pairs?(ast, env), do: metadata_entries(ast, env) != []

  @pair_modules [[:Keyword], [:Map]]

  defp pairs({var, _, context}, env) when is_atom(var) and is_atom(context) do
    case Map.get(env, var) do
      %{pairs: pairs} -> pairs
      nil -> nil
    end
  end

  # A map update (`%{meta | reason: value}`) holds the base map and its new pairs.
  defp pairs({:%{}, _, [{:|, _, [map, pairs]}]}, env) when is_list(pairs), do: merge_pairs(map, pairs, env)
  defp pairs({:%{}, _, pairs}, env) when is_list(pairs), do: keyed(pairs, env)
  defp pairs(list, env) when is_list(list), do: keyed(list, env)
  defp pairs({:++, _, [left, right]}, env), do: merge_pairs(left, right, env)

  defp pairs({:|>, _, [lhs, {callee, meta, args}]}, env) when is_list(args) do
    pairs({callee, meta, [lhs | args]}, env)
  end

  defp pairs({{:., _, [{:__aliases__, _, module}, function]}, _, args}, env) when module in @pair_modules do
    case {function, args} do
      {:merge, [left, right]} -> merge_pairs(left, right, env)
      {put, [base, key, value]} when put in [:put, :put_new] -> merge_pairs(base, [{key, value}], env)
      _other -> nil
    end
  end

  defp pairs(_ast, _env), do: nil

  defp merge_pairs(left, right, env) do
    case {pairs(left, env), pairs(right, env)} do
      {nil, nil} -> nil
      {left, right} -> (left || []) ++ (right || [])
    end
  end

  defp keyed(pairs, env) do
    for {key, value} <- pairs, is_atom(key) or is_binary(key), do: {key, origins(value, env)}
  end

  # The parameters a metadata argument comes straight from (`Logger.info(msg, opts)` in
  # a wrapper whose `opts` parameter is the metadata).
  defp metadata_params({var, _, context}, env) when is_atom(var) and is_atom(context) do
    case Map.get(env, var) do
      %{origins: origins} -> for {:param, index} <- origins, do: index
      nil -> []
    end
  end

  defp metadata_params(_ast, _env), do: []

  ## Calls

  defp evaluate(raw, env, ctx) do
    metadata = raw.metadata ++ lazy_metadata(raw.message)

    %{
      line: raw.line,
      function: raw.function,
      scope: ctx.scope,
      message: origins(raw.message, env),
      formats: Map.get(raw, :formats, []),
      metadata: Enum.flat_map(metadata, &metadata_entries(&1, env)),
      metadata_params: Enum.flat_map(metadata, &metadata_params(&1, env))
    }
  end

  # A lazy message (`fn -> {message, metadata} end`) can return metadata alongside the
  # message; that metadata is checked like any other.
  defp lazy_metadata({:fn, _, clauses}) when is_list(clauses) do
    for {:->, _, [_args, body]} <- clauses, {_message, metadata} <- [last_expression(body)], do: metadata
  end

  defp lazy_metadata(_message), do: []

  defp last_expression({:__block__, _, [_ | _] = exprs}), do: List.last(exprs)
  defp last_expression(expr), do: expr

  defp classify({:., _, [:logger, function]}, meta, args, env, _ctx) when is_atom(function) do
    erlang_call(function, line(meta), args, env)
  end

  defp classify({:., _, [module, function]}, meta, args, env, ctx) when is_atom(function) do
    line = line(meta)

    with {:ok, segments} <- Aliases.resolve(module, line, ctx.aliases),
         true <- Aliases.name(segments) in ctx.loggers do
      build_call(function, line, args, ctx.functions, env)
    else
      _ -> nil
    end
  end

  # Local wrappers take precedence over imports, as local definitions do in Elixir.
  # `import Logger` brings in only Logger's own functions, so the extra logger functions
  # apply only to bare calls imported from the extra loggers.
  defp classify(function, meta, args, env, ctx) when is_atom(function) do
    line = line(meta)

    case Map.get(ctx.wrappers, {ctx.module, function, length(args)}) do
      nil ->
        ctx.imports
        |> Enum.filter(&imports?(&1, function, length(args), line))
        |> Enum.find_value(fn
          {_from, _to, "Logger", _filter} -> build_call(function, line, args, [], env)
          _import -> build_call(function, line, args, ctx.functions, env)
        end)

      roles ->
        wrapper_call(function, line, args, roles)
    end
  end

  defp classify(_callee, _meta, _args, _env, _ctx), do: nil

  defp build_call(function, line, args, functions, env) do
    case {shape(function, length(args), functions), args} do
      {:level, [message]} -> raw(function, line, message, [])
      {:level, [message, metadata | _]} -> raw(function, line, message, [metadata])
      {:log, [_level, message]} -> raw(function, line, message, [])
      {:log, [_level, message, metadata | _]} -> raw(function, line, message, [metadata])
      {:metadata, [metadata]} -> raw(function, line, nil, [metadata])
      # An extra logger function's argument roles aren't configured. An argument holding
      # metadata pairs (a keyword list or map, or a variable assigned one) is metadata;
      # every other argument is part of the message.
      {:extra, args} -> raw(function, line, Enum.reject(args, &pairs?(&1, env)), args)
      _ -> nil
    end
  end

  defp wrapper_call(function, line, args, roles) do
    message = for {:message, index} <- roles, do: Enum.at(args, index)

    metadata =
      for(role <- roles, metadata <- wrapper_metadata(role, args), do: metadata)

    raw(function, line, message, metadata)
  end

  defp wrapper_metadata({:metadata, index}, args), do: [Enum.at(args, index)]
  defp wrapper_metadata({:metadata_value, key, index}, args), do: [[{key, Enum.at(args, index)}]]
  defp wrapper_metadata(_role, _args), do: []

  # Erlang `:logger` calls. A message is a string, a format with its argument list, or
  # a report map; a metadata argument is always a map. The format arguments and report
  # values are part of the message, so `inspect/1` in them counts as `inspect/1` in the
  # message.
  defp erlang_call(function, line, args, env) when function in @erlang_levels, do: erlang_log(function, line, args, env)
  defp erlang_call(:log, line, [_level | args], env), do: erlang_log(:log, line, args, env)

  defp erlang_call(function, line, [metadata], _env) when function in @erlang_metadata do
    raw(function, line, nil, [metadata])
  end

  defp erlang_call(_function, _line, _args, _env), do: nil

  defp erlang_log(function, line, [message], _env), do: raw(function, line, message, [])

  # A second argument is metadata when it is a map (a literal or a variable assigned one);
  # otherwise it is the format's argument list.
  defp erlang_log(function, line, [message, second], env) do
    if map?(second, env) do
      raw(function, line, message, [second])
    else
      erlang_format(function, line, message, second, [])
    end
  end

  defp erlang_log(function, line, [format, format_args, metadata], _env) do
    erlang_format(function, line, format, format_args, [metadata])
  end

  # coveralls-ignore-next-line
  defp erlang_log(_function, _line, _args, _env), do: nil

  # `~p`, `~P`, `~w` and `~W` in an Erlang format string flatten their argument just as
  # `inspect/1` does. Only a literal format (string, interpolated string, sigil or charlist)
  # is scanned.
  defp erlang_format(function, line, format, format_args, metadata) do
    function
    |> raw(line, [format, format_args], metadata)
    |> Map.put(:formats, for(directive <- format_directives(format), do: {directive, line}))
  end

  # A control sequence is `~F.P.PadModC`; `~~` is consumed as a literal tilde.
  @control_sequence ~r/~(?:-?(?:\d+|\*))?(?:\.(?:\d+|\*)?(?:\..)?)?[tlkK]*(.)/su

  defp format_directives(format) do
    for [sequence, control] <- Regex.scan(@control_sequence, format_text(format)),
        control in ~w(p P w W),
        do: sequence
  end

  defp format_text(format) when is_binary(format), do: format
  defp format_text({:<<>>, _, parts}) when is_list(parts), do: Enum.join(for(part <- parts, is_binary(part), do: part))
  defp format_text({sigil, _, [string, _modifiers]}) when sigil in [:sigil_c, :sigil_s], do: format_text(string)

  defp format_text(format) when is_list(format) do
    if Enum.all?(format, &is_integer/1) do
      List.to_string(format)
    else
      ""
    end
  end

  defp format_text(_format), do: ""

  defp map?({:%{}, _, _}, _env), do: true
  defp map?({var, _, context}, env) when is_atom(var) and is_atom(context), do: match?(%{map: true}, Map.get(env, var))
  defp map?({{:., _, [{:__aliases__, _, [:Map]}, function]}, _, _}, _env), do: function in [:merge, :put, :put_new]
  defp map?({:|>, _, [_lhs, rhs]}, env), do: map?(rhs, env)
  defp map?(_ast, _env), do: false

  defp raw(function, line, message, metadata) do
    %{line: line, function: function, message: message, metadata: metadata}
  end

  defp shape(function, _arity, _functions) when function in @levels, do: :level
  defp shape(function, _arity, _functions) when function in [:log, :bare_log], do: :log
  defp shape(function, 1, _functions) when function in [:metadata, :reset_metadata], do: :metadata

  defp shape(function, arity, functions) do
    if {function, arity} in functions do
      :extra
    end
  end

  ## Imports

  # Imports are scoped like aliases: an import of a logger module applies from its line to
  # the end of the enclosing module. The stack holds the end lines of enclosing modules.
  defp collect_imports(ast, aliases, loggers) do
    {_, {imports, _ends}} =
      Macro.traverse(
        ast,
        {[], []},
        fn
          {:import, meta, [module | opts]} = node, {acc, ends} ->
            line = Keyword.get(meta, :line, 0)

            with {:ok, segments} <- Aliases.resolve(module, line, aliases),
                 true <- Aliases.name(segments) in loggers do
              import = {line, List.first(ends, :infinity), Aliases.name(segments), import_filter(opts)}
              {node, {[import | acc], ends}}
            else
              _ -> {node, {acc, ends}}
            end

          node, {acc, ends} = state ->
            if Aliases.module_scope?(node) do
              {node, {acc, [Aliases.scope_end(elem(node, 1)) | ends]}}
            else
              {node, state}
            end
        end,
        fn node, {acc, ends} = state ->
          if Aliases.module_scope?(node) do
            {node, {acc, tl(ends)}}
          else
            {node, state}
          end
        end
      )

    imports
  end

  defp import_filter([opts]) when is_list(opts) do
    {Keyword.get(opts, :only), Keyword.get(opts, :except, [])}
  end

  defp import_filter(_opts), do: {nil, []}

  defp imports?({from, to, _logger, {only, except}}, function, arity, line) do
    Aliases.in_scope?(line, from, to) and included?(only, function, arity) and not listed?(except, function, arity)
  end

  defp included?(nil, _function, _arity), do: true
  defp included?(only, _function, _arity) when only in [:functions, :macros], do: true
  defp included?(only, function, arity) when is_list(only), do: listed?(only, function, arity)
  defp included?(_only, _function, _arity), do: false

  defp listed?(list, function, arity) when is_list(list), do: {function, arity} in list
  # coveralls-ignore-next-line
  defp listed?(_list, _function, _arity), do: false
end
