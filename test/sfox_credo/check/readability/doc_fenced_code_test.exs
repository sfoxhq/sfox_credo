defmodule SfoxCredo.Check.Readability.DocFencedCodeTest do
  use Credo.Test.Case, async: true

  alias SfoxCredo.Check.Readability.DocFencedCode

  @code_message "Use a fenced ```elixir block for code examples instead of indenting."
  @doctest_message "Wrap doctests in a ```elixir fence instead of indenting them."
  @language_message "Tag fenced code blocks with a language."
  @fenced_doctest_message "Tag fenced doctests `elixir` or `iex` so they get IEx highlighting."
  @tilde_message "Use `` ``` `` for code fences, not `~~~`."

  describe "flags" do
    test "an indented doctest inside an admonition" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        > #### Example {: .tip}
        >
        >     iex> run()
        >     :ok
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> assert_issue(%{line_no: 5, message: @doctest_message})
    end

    test "a doctest inside an admonition, in a fence not tagged `elixir`" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        > #### Example {: .tip}
        >
        > ```
        > iex> run()
        > :ok
        > ```
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> assert_issue(%{line_no: 5, message: @fenced_doctest_message})
    end

    test "an indented code block" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        text

            bad_code(:example)
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> assert_issue(%{line_no: 5, message: @code_message})
    end

    test "an indented doctest, once per block, on the `iex>` line" do
      ~S'''
      defmodule CredoSampleModule do
        @doc """
        text

            iex> bad(:doctest)
            :ok

            iex> bad(:again)
            :ok
        """
        def bad(_), do: :ok
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> assert_issue(%{line_no: 5, message: @doctest_message})
    end

    test "an indented doctest using a numbered prompt" do
      ~S'''
      defmodule CredoSampleModule do
        @doc """
        text

            iex(1)> bad(:doctest)
            :ok
        """
        def bad(_), do: :ok
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> assert_issue(%{line_no: 5, message: @doctest_message})
    end

    test "a fence with no language" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        ```
        foo()
        ```
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> assert_issue(%{line_no: 3, message: @language_message})
    end

    test "a doctest in a fence not tagged `elixir`" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        ```shell
        iex> foo()
        ```
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> assert_issue(%{line_no: 3, message: @fenced_doctest_message})
    end

    test "a doctest in a fence with no language gets only the doctest message" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        ```
        iex> foo()
        ```
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> assert_issue(%{line_no: 3, message: @fenced_doctest_message})
    end

    test "a `~~~` fence" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        ~~~elixir
        foo()
        ~~~
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> assert_issue(%{line_no: 3, message: @tilde_message})
    end

    test "code indented four columns past a top-level list item's text" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        - item

              code
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> assert_issue(%{line_no: 5, message: @code_message})
    end

    test "a doctest indented four columns past an ordered item's text" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        1. item

               iex> foo()
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> assert_issue(%{line_no: 5, message: @doctest_message})
    end

    test "indented code in a `@typedoc` and a `~S` heredoc" do
      ~S'''
      defmodule CredoSampleModule do
        @typedoc """
        text

            code
        """
        @type t :: term()

        @doc ~S"""
        text

            code
        """
        def run, do: :ok
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> assert_issues_match([
        %{line_no: 5, message: @code_message},
        %{line_no: 12, message: @code_message}
      ])
    end
  end

  describe "does not flag" do
    test "a doctest in an `elixir` fence" do
      ~S'''
      defmodule CredoSampleModule do
        @doc """
        ```elixir
        iex> good(:doctest)
        :ok
        ```
        """
        def good(_), do: :ok
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> refute_issues()
    end

    test "a doctest in an `iex` fence" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        ```iex
        iex> foo()
        :ok
        ```
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> refute_issues()
    end

    test "an unclosed fence in a block quote, with a doctest in a later fence" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        > ```text
        > output

        ```elixir
        iex> foo()
        :ok
        ```
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> refute_issues()
    end

    test "an `elixir` fence with extra info after the language" do
      ~S'''
      defmodule CredoSampleModule do
        @doc """
        ```elixir title="example"
        iex> good(:doctest)
        :ok
        ```
        """
        def good(_), do: :ok
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> refute_issues()
    end

    test "code under a nested list item" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        - a
          - b

                code
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> refute_issues()
    end

    test "list item continuation lines" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        - item
          continuation

          another paragraph in the item
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> refute_issues()
    end

    test "an indented line straight after paragraph text" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        text
            lazy continuation
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> refute_issues()
    end

    test "indented lines inside a fence" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        text

        ```elixir
        def run do

            :ok
        end
        ```
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> refute_issues()
    end

    test "a fence inside a list item" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        - item

          ```elixir
          iex> foo()
          ```
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> refute_issues()
    end
  end

  describe "params" do
    test "`require_language` defaults to `true`" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        ```
        foo()
        ```
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode)
      |> assert_issue(%{message: @language_message})
    end

    test "`require_language: false` allows fences with no language" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        ```
        foo()
        ```
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode, require_language: false)
      |> refute_issues()
    end

    test "`require_language: false` still flags a doctest in a fence with no language" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        ```
        iex> foo()
        ```
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode, require_language: false)
      |> assert_issue(%{message: @fenced_doctest_message})
    end

    test "`require_language: false` still flags `~~~` fences" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        ~~~
        foo()
        ~~~
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocFencedCode, require_language: false)
      |> assert_issue(%{message: @tilde_message})
    end
  end
end
