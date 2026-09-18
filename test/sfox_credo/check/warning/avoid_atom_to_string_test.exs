defmodule SfoxCredo.Check.Warning.AvoidAtomToStringTest do
  use Credo.Test.Case

  alias SfoxCredo.Check.Warning.AvoidAtomToString

  test "flags Atom.to_string/1 called with an atom literal" do
    """
    defmodule CredoSampleModule do
      def run do
        Atom.to_string(:foo)
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidAtomToString)
    |> assert_issue()
  end

  test "flags Atom.to_string/1 called with a non-literal argument" do
    """
    defmodule CredoSampleModule do
      def run(value) do
        Atom.to_string(value)
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidAtomToString)
    |> assert_issue()
  end

  test "flags Atom.to_string used in pipe form" do
    """
    defmodule CredoSampleModule do
      def run do
        :foo |> Atom.to_string()
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidAtomToString)
    |> assert_issue()
  end

  test "does not flag Atom.to_string(nil)" do
    """
    defmodule CredoSampleModule do
      def run do
        Atom.to_string(nil)
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidAtomToString)
    |> refute_issues()
  end

  test "does not flag Kernel.to_string/1" do
    """
    defmodule CredoSampleModule do
      def run do
        to_string(:foo)
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidAtomToString)
    |> refute_issues()
  end

  test "does not flag to_string/1 on an unrelated module" do
    """
    defmodule CredoSampleModule do
      def run do
        Integer.to_string(1)
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidAtomToString)
    |> refute_issues()
  end

  test "flags a renamed alias of Atom" do
    """
    defmodule CredoSampleModule do
      alias Atom, as: A

      def run do
        A.to_string(:foo)
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidAtomToString)
    |> assert_issue()
  end

  test "flags a call via a grouped alias of Atom" do
    """
    defmodule CredoSampleModule do
      alias Elixir.{Atom}

      def run do
        Atom.to_string(:foo)
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidAtomToString)
    |> assert_issue()
  end

  test "does nothing when Atom.to_string/1 has been imported" do
    """
    defmodule CredoSampleModule do
      def run do
        import Kernel, except: [to_string: 1]
        import Atom, only: [to_string: 1]
        to_string(:foo)
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidAtomToString)
    |> refute_issues()
  end

  test "does not flag an unrelated module aliased as Atom" do
    """
    defmodule CredoSampleModule do
      alias MyApp.Atom

      def run do
        Atom.to_string(:foo)
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidAtomToString)
    |> refute_issues()
  end

  test "does not flag an unrelated module aliased as Atom via as:" do
    """
    defmodule CredoSampleModule do
      alias MyApp.Atom, as: Atom

      def run do
        Atom.to_string(:foo)
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidAtomToString)
    |> refute_issues()
  end

  test "does not flag an unrelated module aliased via a group that shares the Atom name" do
    """
    defmodule CredoSampleModule do
      alias MyApp.{Atom}

      def run do
        Atom.to_string(:foo)
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidAtomToString)
    |> refute_issues()
  end

  test "an alias declared after the call site does not retroactively apply" do
    """
    defmodule CredoSampleModule do
      def run do
        Atom.to_string(:foo)
      end

      alias MyApp.Atom
    end
    """
    |> to_source_file()
    |> run_check(AvoidAtomToString)
    |> assert_issue()
  end

  test "does not flag to_string/1 called on a variable" do
    """
    defmodule CredoSampleModule do
      def run(mod) do
        mod.to_string(:foo)
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidAtomToString)
    |> refute_issues()
  end

  test "does not flag to_string/1 called on the result of a function call" do
    """
    defmodule CredoSampleModule do
      def run do
        resolve_module().to_string(:foo)
      end

      defp resolve_module, do: Atom
    end
    """
    |> to_source_file()
    |> run_check(AvoidAtomToString)
    |> refute_issues()
  end

  test "resolves an alias declared with options other than `:as`" do
    """
    defmodule CredoSampleModule do
      alias Atom, warn: false

      def run do
        Atom.to_string(:foo)
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidAtomToString)
    |> assert_issue()
  end
end
