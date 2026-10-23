defmodule SfoxCredo.Check.Warning.AshCallInEnumTest do
  use Credo.Test.Case, async: true

  alias SfoxCredo.Check.Warning.AshCallInEnum

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

  test "does not flag Ash calls in other Enum functions" do
    """
    defmodule CredoSampleModule do
      def run(ids) do
        Enum.filter(ids, &Ash.exists?(Customer, &1))
      end
    end
    """
    |> to_source_file()
    |> run_check(AshCallInEnum)
    |> refute_issues()
  end

  test "does not flag a named function reference" do
    """
    defmodule CredoSampleModule do
      def run(ids) do
        Enum.map(ids, &fetch/1)
      end

      defp fetch(id), do: Ash.get!(Customer, id)
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
end
