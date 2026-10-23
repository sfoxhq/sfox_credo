# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/sfox_credo/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule SfoxCredo.Check.Readability.DisableWithoutReasonTest do
  use Credo.Test.Case, async: true

  alias SfoxCredo.Check.Readability.DisableWithoutReason

  test "flags disable-for-next-line without a reason" do
    """
    defmodule CredoSampleModule do
      def run(value) do
        # credo:disable-for-next-line Credo.Check.Warning.IoInspect
        IO.inspect(value)
      end
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> assert_issue(%{line_no: 3, trigger: "credo:disable-for-next-line"})
  end

  test "flags disable-for-this-file without a reason" do
    """
    # credo:disable-for-this-file
    defmodule CredoSampleModule do
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> assert_issue(%{line_no: 1, trigger: "credo:disable-for-this-file"})
  end

  test "flags disable-for-previous-line and disable-for-lines without a reason" do
    """
    defmodule CredoSampleModule do
      def run(value) do
        IO.inspect(value)
        # credo:disable-for-previous-line Credo.Check.Warning.IoInspect

        # credo:disable-for-lines:2
        IO.inspect(value)
      end
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> assert_issues(fn issues ->
      assert issues
             |> Enum.map(& &1.line_no)
             |> Enum.sort() == [4, 6]
    end)
  end

  test "flags a reason on the same line, because Credo then ignores the disable" do
    """
    defmodule CredoSampleModule do
      def run(value) do
        # credo:disable-for-next-line Credo.Check.Warning.IoInspect -- debug output
        IO.inspect(value)
      end
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> assert_issues(fn issues ->
      assert [missing_reason, text_after_check] = Enum.sort_by(issues, & &1.message)
      assert missing_reason.message =~ "Add the reason"
      assert text_after_check.message =~ "matches nothing"
      assert Enum.map(issues, & &1.line_no) == [3, 3]
    end)
  end

  test "flags text after the check name even with a reason above" do
    """
    defmodule CredoSampleModule do
      def run(value) do
        # Debug output for the support team.
        # credo:disable-for-next-line Credo.Check.Warning.IoInspect -- debug output
        IO.inspect(value)
      end
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> assert_issue(fn issue ->
      assert issue.line_no == 4
      assert issue.trigger == "credo:disable-for-next-line"
      assert issue.message =~ "matches nothing"
    end)
  end

  test "flags two check names after a disable" do
    """
    defmodule CredoSampleModule do
      def run(value) do
        # Debug output for the support team.
        # credo:disable-for-next-line Credo.Check.Warning.IoInspect Credo.Check.Warning.Dbg
        IO.inspect(value)
      end
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> assert_issue(fn issue -> assert issue.message =~ "matches nothing" end)
  end

  test "does not flag a regex check name with spaces" do
    """
    defmodule CredoSampleModule do
      def run(value) do
        # Debug output for the support team.
        # credo:disable-for-next-line /Io Inspect/
        IO.inspect(value)
      end
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> refute_issues()
  end

  test "flags a disable with a capitalized `Credo:` prefix, which Credo honors" do
    """
    defmodule CredoSampleModule do
      def run(value) do
        # Credo:disable-for-next-line Credo.Check.Warning.IoInspect
        IO.inspect(value)
      end
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> assert_issue(fn issue -> assert issue.line_no == 3 end)
  end

  test "does not parse a file without a directive" do
    """
    defmodule CredoSampleModule do
      def run(value), do: value
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> refute_issues()
  end

  test "does not flag a disable with a reason on the line above" do
    """
    defmodule CredoSampleModule do
      def run(value) do
        # The CLI prints this value for the operator.
        # credo:disable-for-next-line Credo.Check.Warning.IoInspect
        IO.inspect(value)
      end
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> refute_issues()
  end

  test "does not flag a reason higher in the same comment block" do
    """
    # The DSL macros must come before the module docs.
    # quokka:skip-module-directives
    # credo:disable-for-this-file Credo.Check.Readability.StrictModuleLayout
    defmodule CredoSampleModule do
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> refute_issues()
  end

  test "flags a disable with only tool directives above it" do
    """
    # quokka:skip-module-directives
    # coveralls-ignore-next-line
    # credo:disable-for-this-file Credo.Check.Readability.StrictModuleLayout
    defmodule CredoSampleModule do
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> assert_issues(fn issues ->
      assert issues
             |> Enum.map(&{&1.line_no, &1.trigger})
             |> Enum.sort() == [
               {1, "quokka:skip-module-directives"},
               {3, "credo:disable-for-this-file"}
             ]
    end)
  end

  test "flags quokka:skip directives without a reason" do
    """
    # quokka:skip-module-reordering
    defmodule CredoSampleModule do
      # quokka:skip-sort
      @values [:b, :a]
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> assert_issues(fn issues ->
      assert issues
             |> Enum.map(&{&1.line_no, &1.trigger})
             |> Enum.sort() == [{1, "quokka:skip-module-reordering"}, {3, "quokka:skip-sort"}]
    end)
  end

  test "does not flag quokka:sort or coveralls-ignore without a reason" do
    """
    # coveralls-ignore-next-line
    defmodule CredoSampleModule do
      # quokka:sort
      @values [:a, :b]
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> refute_issues()
  end

  test "one reason covers stacked directives across an empty comment line" do
    """
    # DSL macros must come before module documentation for this module.
    #
    # quokka:skip-module-directives
    # credo:disable-for-this-file Credo.Check.Readability.StrictModuleLayout
    defmodule CredoSampleModule do
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> refute_issues()
  end

  test "flags a disable with a blank line between it and the reason" do
    """
    # The DSL macros must come before the module docs.

    # credo:disable-for-this-file Credo.Check.Readability.StrictModuleLayout
    defmodule CredoSampleModule do
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> assert_issue()
  end

  test "flags a disable with an empty comment above it" do
    """
    #
    # credo:disable-for-this-file Credo.Check.Readability.StrictModuleLayout
    defmodule CredoSampleModule do
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> assert_issue()
  end

  test "does not take a trailing comment on a code line as a reason" do
    """
    defmodule CredoSampleModule do
      def run(value) do
        value = value + 1 # bump the value
        # credo:disable-for-next-line Credo.Check.Warning.IoInspect
        IO.inspect(value)
      end
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> assert_issue()
  end

  test "flags each disable without a reason as one issue" do
    """
    defmodule CredoSampleModule do
      def run(value) do
        # credo:disable-for-next-line Credo.Check.Warning.IoInspect
        IO.inspect(value)
        # credo:disable-for-next-line Credo.Check.Warning.IoInspect
        IO.inspect(value)
      end
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "accepts a reason on the line after an opening bracket" do
    """
    defmodule CredoSampleModule do
      def run(value) do
        IO.puts([
          # Debug output for the support team.
          # credo:disable-for-next-line Credo.Check.Warning.IoInspect
          IO.inspect(value)
        ])
      end
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> refute_issues()
  end

  test "accepts a reason that starts with a word and a colon" do
    """
    defmodule CredoSampleModule do
      def run(value) do
        # TODO:remove once upstream fixed
        # credo:disable-for-next-line Credo.Check.Warning.IoInspect
        IO.inspect(value)
      end
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> refute_issues()
  end

  test "does not take a capitalized `Credo:` directive as a reason" do
    """
    defmodule CredoSampleModule do
      def run(value) do
        # Credo:disable-for-next-line Credo.Check.Warning.Dbg
        # credo:disable-for-next-line Credo.Check.Warning.IoInspect
        IO.inspect(value)
      end
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "accepts a URL as a reason" do
    """
    # https://github.com/rrrene/credo/issues/1
    # credo:disable-for-this-file Credo.Check.Readability.StrictModuleLayout
    defmodule CredoSampleModule do
    end
    """
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> refute_issues()
  end

  test "does not flag credo:disable text in a string" do
    ~S'''
    defmodule CredoSampleModule do
      @moduledoc """
      # credo:disable-for-this-file
      """
    end
    '''
    |> to_source_file()
    |> run_check(DisableWithoutReason)
    |> refute_issues()
  end
end
