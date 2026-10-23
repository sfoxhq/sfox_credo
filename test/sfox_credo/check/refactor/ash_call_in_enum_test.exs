# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/sfox_credo/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule SfoxCredo.Check.Refactor.AshCallInEnumTest do
  use Credo.Test.Case, async: true

  alias SfoxCredo.Check.Refactor.AshCallInEnum

  # Functions `Ash` exports that the check leaves out on purpose. Bulk actions take
  # a whole batch. The rest build a query or a filter, check authorization, or describe
  # options. Functions named `*_opts` describe options and are left out by name.
  not_data_layer = ~w(
    bulk_create bulk_create! bulk_destroy bulk_destroy! bulk_update bulk_update!
    data_layer_query data_layer_query! pkey_filter stream_opt_keys
  )a

  # These functions are questionable. They _can_ cause queries.
  maybe_data_layer = ~w(can can? can_do_all can_do_all? can_see_fields can_see_fields?)a

  @not_data_layer not_data_layer ++ maybe_data_layer

  # Catches drift when `Ash` is upgraded: a renamed or removed function in the check's
  # list, or a new `Ash` function that is in neither list.
  describe "the data layer function list" do
    test "names only functions that Ash exports" do
      exported = ash_functions()

      assert AshCallInEnum.data_layer_functions() -- exported == []
    end

    test "covers every function Ash exports" do
      unclassified =
        for function <- ash_functions(),
            not String.ends_with?(to_string(function), "_opts"),
            function not in AshCallInEnum.data_layer_functions(),
            function not in @not_data_layer,
            do: function

      assert unclassified == [], """
      Ash exports functions that are in neither the check's data layer list nor this
      test's @not_data_layer list: #{inspect(unclassified)}
      """
    end

    test "doesn't list a function as both" do
      assert Enum.filter(@not_data_layer, &(&1 in AshCallInEnum.data_layer_functions())) == []
    end
  end

  test "flags an Ash call in an Enum.map function" do
    """
    defmodule CredoSampleModule do
      def run(ids) do
        Enum.map(ids, fn id -> Ash.get!(Customer, id) end)
      end
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> assert_issue(%{line_no: 3, trigger: "Ash.get!"})
  end

  test "flags an Ash call in a piped Enum.each function" do
    """
    defmodule CredoSampleModule do
      def run(customers) do
        customers
        |> Enum.each(fn customer ->
          customer
          |> Ash.Changeset.for_update(:archive)
          |> Ash.update!()
        end)
      end
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> assert_issue(%{line_no: 7, trigger: "Ash.update!"})
  end

  test "flags an Ash call in a capture" do
    """
    defmodule CredoSampleModule do
      def run(ids, customers) do
        Enum.map(ids, &Ash.get!(Customer, &1))
        Enum.map(customers, &Ash.load!/2)
      end
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [3, 4] end)
  end

  test "flags an Ash call in a for body" do
    """
    defmodule CredoSampleModule do
      def run(customers) do
        for customer <- customers, into: %{} do
          {customer.id, Ash.load!(customer, :documents)}
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> assert_issue(%{line_no: 4, trigger: "Ash.load!"})
  end

  test "flags an Ash call in a for filter or a later generator, not the first generator" do
    """
    defmodule CredoSampleModule do
      def run(query, queries) do
        for customer <- Ash.read!(query), Ash.exists?(Customer, customer.id), do: customer
        for query <- queries, customer <- Ash.read!(query), do: customer
      end
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.line_no, &1.trigger}) == [{3, "Ash.exists?"}, {4, "Ash.read!"}]
    end)
  end

  test "flags an Ash call in nested loops once" do
    """
    defmodule CredoSampleModule do
      def run(groups) do
        Enum.map(groups, fn ids ->
          Enum.map(ids, fn id -> Ash.get!(Customer, id) end)
        end)
      end
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> assert_issue()
  end

  test "does not flag an Ash call that makes the collection" do
    """
    defmodule CredoSampleModule do
      def run(query) do
        Enum.map(Ash.read!(query), fn customer -> customer.id end)

        query |> Ash.read!() |> Enum.each(&IO.puts(&1.id))

        for customer <- Ash.read!(query), do: customer.id
      end
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> refute_issues()
  end

  test "does not flag Ash.Query and Ash.Changeset builders" do
    """
    defmodule CredoSampleModule do
      def run(params_list) do
        Enum.map(params_list, fn params ->
          Ash.Changeset.for_create(Customer, :create, params)
        end)

        Enum.map(params_list, &Ash.Query.filter(Customer, id == ^&1.id))
      end
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> refute_issues()
  end

  test "flags Ash calls in other Enum and Stream functions" do
    """
    defmodule CredoSampleModule do
      def run(ids, customers) do
        Enum.filter(ids, &Ash.exists?(Customer, &1))
        Enum.reduce(customers, [], fn customer, acc -> [Ash.load!(customer, :documents) | acc] end)
        customers |> Stream.map(&Ash.reload!/1) |> Enum.to_list()
        Stream.transform(ids, nil, fn id, acc -> {[Ash.get!(Customer, id)], acc} end)
      end
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.line_no, &1.trigger}) == [
               {3, "Ash.exists?"},
               {4, "Ash.load!"},
               {5, "Ash.reload!"},
               {6, "Ash.get!"}
             ]
    end)
  end

  test "does not flag Stream functions that produce or wrap a stream" do
    """
    defmodule CredoSampleModule do
      def run(query) do
        Stream.resource(fn -> 0 end, fn offset -> {Ash.read!(query, page: [offset: offset]), offset + 100} end, fn _ -> :ok end)
        Stream.unfold(0, fn offset -> {Ash.read!(query, page: [offset: offset]), offset + 100} end)
        Stream.repeatedly(fn -> Ash.read_one!(query) end)
        Stream.iterate(Ash.read_first!(query), fn record -> Ash.reload!(record) end)
        Stream.transform(query, fn -> Ash.read!(query) end, fn x, acc -> {[x], acc} end, fn _ -> :ok end)
      end
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> refute_issues()
  end

  test "flags Ash.unpaginated_read" do
    """
    defmodule CredoSampleModule do
      def run(queries) do
        Enum.map(queries, &Ash.unpaginated_read!/1)
      end
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> assert_issue(%{trigger: "Ash.unpaginated_read!"})
  end

  test "does not flag bulk actions" do
    """
    defmodule CredoSampleModule do
      def run(batches) do
        Enum.each(batches, &Ash.bulk_create!(&1, Customer, :create))
        Enum.each(batches, &Ash.bulk_update!(&1, :archive, %{}))
        Enum.each(batches, &Ash.bulk_destroy!(&1, :destroy, %{}))
      end
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> refute_issues()
  end

  test "does not flag a loop over chunks" do
    """
    defmodule CredoSampleModule do
      def run(customers) do
        Enum.each(Enum.chunk_every(customers, 100), &Ash.load!(&1, :documents))
        customers |> Stream.chunk_every(100) |> Enum.each(&Ash.load!(&1, :documents))
        customers |> Enum.chunk_by(& &1.region) |> Enum.map(&Ash.load!(&1, :documents))
        for chunk <- Enum.chunk_every(customers, 100), do: Ash.load!(chunk, :documents)
      end
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> refute_issues()
  end

  test "flags Ash, Enum and Stream through an alias" do
    """
    defmodule CredoSampleModule do
      alias Ash, as: A
      alias Enum, as: E

      def run(ids) do
        E.map(ids, &A.get!(Customer, &1))
        Enum.map(ids, &Elixir.Ash.get!(Customer, &1))
      end
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [6, 7] end)
  end

  test "does not flag a module aliased as Enum or Ash" do
    """
    defmodule CredoSampleModule.EnumAlias do
      alias MyApp.Enum

      def run(ids), do: Enum.map(ids, &Ash.get!(Customer, &1))
    end

    defmodule CredoSampleModule.AshAlias do
      alias MyApp.Ash

      def run(ids), do: Enum.map(ids, &Ash.get!(Customer, &1))
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> refute_issues()
  end

  test "flags a local function that calls Ash, called or captured in a loop" do
    """
    defmodule CredoSampleModule do
      def run(ids) do
        Enum.map(ids, &fetch/1)
        Enum.map(ids, fn id -> fetch(id) end)
        Enum.map(ids, &(&1 |> fetch()))
        for id <- ids, do: fetch(id, :documents)
      end

      defp fetch(id, load \\\\ []) when is_binary(id) do
        Customer |> Ash.get!(id) |> Ash.load!(load)
      end
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.line_no, &1.trigger}) == [
               {3, "fetch/1"},
               {4, "fetch/1"},
               {5, "fetch/1"},
               {6, "fetch/2"}
             ]

      assert hd(issues).message =~ "`fetch/1` calls `Ash.get!`"
    end)
  end

  test "flags a zero-arity local function, in a for with a filter" do
    """
    defmodule CredoSampleModule do
      def run(ids) do
        for id <- ids, id > 0, do: {id, current()}
      end

      defp current, do: Ash.read_one!(Setting)
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> assert_issue(%{line_no: 3, trigger: "current/0"})
  end

  test "flags a loop in a script outside any module" do
    """
    for attrs <- [%{name: "a"}, %{name: "b"}] do
      seed(attrs)
    end

    def seed(attrs), do: Ash.create!(Customer, attrs)
    """
    |> to_source_file("priv/repo/seeds.exs")
    |> run_check(AshCallInEnum)
    |> assert_issue(%{line_no: 2, trigger: "seed/1"})
  end

  test "does not follow local functions more than one level" do
    """
    defmodule CredoSampleModule do
      def run(ids) do
        Enum.map(ids, &fetch/1)
      end

      defp fetch(id), do: get(id)
      defp get(id), do: Ash.get!(Customer, id)
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> refute_issues()
  end

  test "does not follow a local function of another module" do
    """
    defmodule CredoSampleModule do
      defmodule Repo do
        def fetch(id), do: Ash.get!(Customer, id)
      end

      def run(ids) do
        Enum.map(ids, &fetch/1)
      end

      defp fetch(id), do: id
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> refute_issues()
  end

  test "does not flag a local function that doesn't call Ash" do
    """
    defmodule CredoSampleModule do
      def run(ids) do
        Enum.map(ids, &label/1)
      end

      defp label(id), do: "customer \#{id}"
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> refute_issues()
  end

  test "does not flag a call on a module that ends in Ash" do
    """
    defmodule CredoSampleModule do
      def run(ids) do
        Enum.map(ids, &MyApp.Ash.get!(&1))
        Enum.map(ids, &__MODULE__.Ash.get!(&1))
      end
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> refute_issues()
  end

  test "does not flag files in a test directory" do
    """
    defmodule CredoSampleModuleTest do
      test "verifies each type" do
        for type <- [:email, :phone], do: Ash.update!(changeset(type))
      end
    end
    """
    |> to_source_file("test/sample_test.exs")
    |> run_check(AshCallInEnum)
    |> refute_issues()
  end

  for path <- ["apps/app/test/support/factory.ex", "lib/my_app/sample_test.exs", Path.join(File.cwd!(), "test/x.ex")] do
    test "does not flag the test file #{path}" do
      """
      defmodule CredoSampleModule do
        def run(types), do: for(type <- types, do: Ash.update!(changeset(type)))
      end
      """
      |> to_source_file(unquote(path))
      |> run_check(AshCallInEnum)
      |> refute_issues()
    end
  end

  for path <- ["lib/my_app/test/x.ex", "apps/test/lib/x.ex", "lib/my_app/latest/x.ex"] do
    test "flags application code at #{path}" do
      """
      defmodule CredoSampleModule do
        def run(types), do: for(type <- types, do: Ash.update!(changeset(type)))
      end
      """
      |> to_source_file(unquote(path))
      |> run_check(AshCallInEnum)
      |> assert_issue()
    end
  end

  test "flags files in a test directory when include_tests is true" do
    """
    defmodule CredoSampleModuleTest do
      test "verifies each type" do
        for type <- [:email, :phone], do: Ash.update!(changeset(type))
      end
    end
    """
    |> to_source_file("apps/app/test/sample_test.exs")
    |> run_check(AshCallInEnum, include_tests: true)
    |> assert_issue()
  end

  defp ash_functions do
    :functions
    |> Ash.__info__()
    |> Keyword.keys()
    |> Enum.uniq()
  end
end
