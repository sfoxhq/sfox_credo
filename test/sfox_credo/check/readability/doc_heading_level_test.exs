# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/sfox_credo/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule SfoxCredo.Check.Readability.DocHeadingLevelTest do
  use Credo.Test.Case, async: true

  alias SfoxCredo.Check.Readability.DocHeadingLevel

  @level_one_message "Start documentation headings at `##`; `#` is reserved for the module name."
  @skip_message "Heading levels should increase by one."
  @admonition_level_message "Use `###` or `####` for admonition titles; ExDoc renders no others."

  describe "flags" do
    test "a `#` heading in `@moduledoc`, `@doc` and `@typedoc`" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        # Module
        """

        @typedoc """
        # Type
        """
        @type t :: term()

        @doc """
        # Function
        """
        def run, do: :ok
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> assert_issues_match([
        %{line_no: 3, message: @level_one_message},
        %{line_no: 7, message: @level_one_message},
        %{line_no: 12, message: @level_one_message}
      ])
    end

    test "a setext level-1 heading, reported on the text line" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        Intro.

        Title
        =====
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> assert_issue(%{line_no: 5, message: @level_one_message})
    end

    test "a skipped level, reported on the deeper heading" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        ## A

        #### B
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> assert_issue(%{line_no: 5, message: @skip_message})
    end

    test "a `#` heading in a `~S` heredoc" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc ~S"""
        Text.

        # Title
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> assert_issue(%{line_no: 5, message: @level_one_message})
    end

    test "an admonition title at a level ExDoc doesn't render" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        ## A

        > ## Note {: .info}
        >
        > Text.
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> assert_issue(%{line_no: 5, message: @admonition_level_message})
    end

    test "an admonition with an unknown class" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        > #### Careful {: .warn}
        >
        > Text.
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> assert_issue(fn issue ->
        assert issue.line_no == 3
        assert issue.message =~ "Unknown admonition class `.warn`"
      end)
    end

    test "an admonition with both a bad level and an unknown class" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        > # Careful {: .warn}
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> assert_issues(fn issues -> assert length(issues) == 2 end)
    end

    test "a classed heading after text in a block quote, which isn't an admonition" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        ## A

        > Text.
        >
        > #### Note {: .info}
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> assert_issue(%{line_no: 7, message: "Heading levels should increase by one."})
    end

    test "a `#` heading inside a plain block quote" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        > # Quoted
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> assert_issue(%{line_no: 3, message: @level_one_message})
    end

    test "a skipped level after an admonition, compared with the heading before it" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        ## A

        > #### Tip {: .tip}
        >
        > Text.

        #### B
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> assert_issue(%{line_no: 9, message: @skip_message})
    end
  end

  describe "does not flag" do
    test "admonition titles at `###` and `####` with each supported class" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        ## A

        > #### Warning {: .warning}

        > #### Error {: .error}

        > ### Info {: .info}

        > #### Tip {: .tip}

        > #### Neutral {: .neutral}
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> refute_issues()
    end

    test "an admonition as the first thing in a `@doc`" do
      ~S'''
      defmodule CredoSampleModule do
        @doc """
        > #### Note {: .info}
        >
        > Text.
        """
        def run, do: :ok
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> refute_issues()
    end

    test "an admonition whose title follows blank `>` lines" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        ## A

        >
        > #### Note {: .info}
        >
        > Text.
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> refute_issues()
    end

    test "an admonition with a supported class among others" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        > #### Note {: .info .wide}
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> refute_issues()
    end

    test "an admonition inside a list item" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        ## A

        - item

          > #### Note {: .info}
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> refute_issues()
    end

    test "going back up a level" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        ## A

        ### B

        ## C
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> refute_issues()
    end

    test "`###` as the first heading in a `@doc`" do
      ~S'''
      defmodule CredoSampleModule do
        @doc """
        ### A
        """
        def run, do: :ok
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> refute_issues()
    end

    test "`# comment` inside `elixir` and `shell` fences" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        ```elixir
        # comment
        ```

        ```shell
        # comment
        ```
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> refute_issues()
    end

    test "`# comment` in an indented code block" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        Text.

            # comment
            foo()

            # another comment
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> refute_issues()
    end

    test "`#hashtag` at the start of a line" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        #hashtag
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> refute_issues()
    end

    test "headings in separate docs are compared separately" do
      ~S'''
      defmodule CredoSampleModule do
        @doc """
        ## A
        """
        def a, do: :a

        @doc """
        #### B
        """
        def b, do: :b
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> refute_issues()
    end

    test "a setext level-2 heading" do
      ~S'''
      defmodule CredoSampleModule do
        @moduledoc """
        text
        ---
        """
      end
      '''
      |> to_source_file()
      |> run_check(DocHeadingLevel)
      |> refute_issues()
    end
  end
end
