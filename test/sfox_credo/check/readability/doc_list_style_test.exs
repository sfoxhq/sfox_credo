defmodule SfoxCredo.Check.Readability.DocListStyleTest do
  use Credo.Test.Case, async: true

  alias SfoxCredo.Check.Readability.DocListStyle

  @marker_message "Use `-` for Markdown list items, not `*` or `+`."
  @indent_message "Don't indent Markdown list items from the surrounding text."

  describe "flags" do
    test "a `*` item and an indented item inside an admonition" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        > #### Note {: .info}
        >
        > * star
        >
        > text
        >
        >   - indented
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> assert_issues(fn issues ->
        assert issues
               |> Enum.map(& &1.line_no)
               |> Enum.sort() == [5, 9]
      end)
    end

    test "`+` and `*` markers at column 0" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        Text.

        + plus
        * star
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> assert_issues_match([
        %{line_no: 5, message: @marker_message},
        %{line_no: 6, message: @marker_message}
      ])
    end

    test "an item indented after a paragraph and a blank line" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        Text.

          - item
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> assert_issue(%{line_no: 5, message: @indent_message})
    end

    test "an indented `+` item gets a marker issue and an indentation issue" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        Text.

          + item
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> assert_issues_match([
        %{line_no: 5, message: @marker_message},
        %{line_no: 5, message: @indent_message}
      ])
    end

    test "a nested item indented past its parent's content column" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        - a
            - b
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> assert_issue(%{line_no: 4, message: @indent_message})
    end

    test "a sibling indented differently from the earlier items" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        - a
         - b
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> assert_issue(%{line_no: 4, message: @indent_message})
    end

    test "the example from the request" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        text

          + bad
          * bad
          - bad
        - good
          - good
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> assert_issues_match([
        %{line_no: 5, message: @marker_message},
        %{line_no: 5, message: @indent_message},
        %{line_no: 6, message: @marker_message},
        %{line_no: 6, message: @indent_message},
        %{line_no: 7, message: @indent_message}
      ])
    end

    test "a list item in a `@doc`" do
      ~S'''
      defmodule CredoSampleModule do
        @doc """
        * item
        """
        def run, do: :ok
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> assert_issue(%{line_no: 3, message: @marker_message})
    end

    test "a list item in a `@typedoc`" do
      ~S'''
      defmodule CredoSampleModule do
        @typedoc """
        Text.

          - item
        """
        @type t :: term()
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> assert_issue(%{line_no: 5, message: @indent_message})
    end

    test "a list item in a `~S` heredoc" do
      ~S'''
      defmodule CredoSampleModule do
        @doc ~S"""
        Text.

          + item
        """
        def run, do: :ok
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> assert_issues_match([
        %{line_no: 5, message: @marker_message},
        %{line_no: 5, message: @indent_message}
      ])
    end

    test "a list item in an interpolated heredoc" do
      ~S'''
      defmodule CredoSampleModule do
        @name "x"

        @doc """
        Uses #{@name}.

        * item
        """
        def run, do: :ok
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> assert_issue(%{line_no: 7, message: @marker_message})
    end

    test "a single-line doc reports on the attribute's line" do
      ~S'''
      defmodule CredoSampleModule do
        @doc "Text.\n\n* item"
        def run, do: :ok
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> assert_issue(%{line_no: 2, message: @marker_message})
    end

    test "a heredoc with escaped newlines reports on the source line" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        Text.\n\nMore text, \
        continued.

        * item
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> assert_issue(%{line_no: 6, message: @marker_message})
    end

    test "a heredoc with a multi-line interpolation reports on the source line" do
      ~S'''
      defmodule CredoSampleModule do
        @doc """
        Uses #{
          "x"
        }.

        * item
        """
        def run, do: :ok
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> assert_issue(%{line_no: 7, message: @marker_message})
    end

    test "a heredoc `@doc` on line 10 reports doc line 3 on line 13" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc false

        def a, do: :a

        def b, do: :b

        def c, do: :c

        @doc """
        Text.

        * item
        """
        def run, do: :ok
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> assert_issue(fn issue -> assert issue.line_no == 13 end)
    end
  end

  describe "does not flag" do
    test "nested items under their parents' text" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        - a
          - b
            - c
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> refute_issues()
    end

    test "a bullet nested under an ordered item" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        1. a
           - b
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> refute_issues()
    end

    test "thematic breaks" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        Text.

        * * *

        ***

        - - -
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> refute_issues()
    end

    test "emphasis at the start of a line" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        *emphasis* at line start

        **strong** at line start
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> refute_issues()
    end

    test "`+` and `*` items inside a fence" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        ```text
        + plus
          * star
        ```
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> refute_issues()
    end

    test "`@doc false` and `@doc since:`" do
      ~S'''
      defmodule CredoSampleModule do
        @doc false
        def a, do: :a

        @doc since: "1.0"
        def b, do: :b
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> refute_issues()
    end

    test "an indented item after a blank line with no list open (indented code)" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        Text.

            - foo
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> refute_issues()
    end

    test "docs built at compile time" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc File.read!("README.md")
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> refute_issues()
    end
  end

  describe "params" do
    test "`marker` defaults to `-`" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        - item
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> refute_issues()
    end

    test "`marker: \"*\"` requires `*` and names it in the message" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        * good
        - bad
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle, marker: "*")
      |> assert_issue(%{line_no: 4, message: "Use `*` for Markdown list items, not `-` or `+`."})
    end

    test "`check_indentation` defaults to `true`" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        Text.

          - item
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle)
      |> assert_issue()
    end

    test "`check_indentation: false` reports only the marker" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        Text.

          - item
          + item
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocListStyle, check_indentation: false)
      |> assert_issue(%{line_no: 6, message: @marker_message})
    end

    # `run_check/3` runs the check in a linked process, so a configuration error is
    # asserted against `run/2` directly.
    test "`marker` must be `-`, `*` or `+`" do
      source_file = to_source_file("defmodule CredoSampleModule do\nend\n")

      for marker <- ["•", :*] do
        assert_raise ArgumentError, ~r/marker must be one of/, fn -> DocListStyle.run(source_file, marker: marker) end
      end
    end
  end
end
