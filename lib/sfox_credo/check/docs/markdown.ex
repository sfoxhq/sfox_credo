# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/sfox_credo/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule SfoxCredo.Check.Docs.Markdown do
  @moduledoc false

  # A line-based scanner over the CommonMark block starts that the documentation checks
  # need. It is not a Markdown parser: it reports where fences, indented code blocks, list
  # items and headings begin, with 0-based line offsets into the scanned text, and leaves
  # every decision to the checks.
  #
  # Events:
  #
  # - `{:fence_open, offset, fence_char, info_string}`
  # - `{:fence_close, offset}`; a fence ended by its list item, block quote or the end of
  #   the text closes at the first line past it
  # - `{:indented_code, offset, first_line_text}`, once per block
  # - `{:list_item, offset, indent, marker, content_col, parent_col}`, for bullet items
  #   only; `parent_col` is the `content_col` of the enclosing list item, or 0 at the top
  #   level
  # - `{:heading, offset, level, style, text}`, where style is `:atx` or `:setext` and
  #   text is the heading's text (without the `#` markers or a closing `#` sequence)
  # - `{:quote_open, offset}` and `{:quote_close, offset}` around the events of a block
  #   quote's content. The content (each line with its `>` marker and one following space
  #   removed) is scanned as its own document, so its offsets are still offsets into the
  #   scanned text and its indentation is relative to the quote
  #
  # Ordered list items are tracked so nesting under them works, but they produce no event.
  #
  # A block quote ends at the first line that does not start with `>`; lazy continuation
  # lines are not part of it.

  @type offset :: non_neg_integer()
  @type event ::
          {:fence_open, offset(), String.t(), String.t()}
          | {:fence_close, offset()}
          | {:indented_code, offset(), String.t()}
          | {:list_item, offset(), non_neg_integer(), String.t(), non_neg_integer(), non_neg_integer()}
          | {:heading, offset(), 1..6, :atx | :setext, String.t()}
          | {:quote_open, offset()}
          | {:quote_close, offset()}

  @doc false
  @spec lines(String.t()) :: [String.t()]
  def lines(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim_trailing(&1, "\r"))
  end

  @doc false
  @spec scan(String.t()) :: [event()]
  def scan(text) do
    initial = %{
      fence: nil,
      code: nil,
      prev_paragraph?: false,
      para_start: 0,
      para_text: "",
      quote: nil,
      stack: [],
      events: []
    }

    lines = lines(text)

    lines
    |> Enum.with_index()
    |> Enum.reduce(initial, &scan_line/2)
    |> close_quote()
    |> close_fence(length(lines))
    |> Map.fetch!(:events)
    |> Enum.reverse()
  end

  # A fence still open at the end of the text closes there, one past its last line.
  defp close_fence(%{fence: nil} = state, _offset), do: state
  defp close_fence(state, offset), do: emit(%{state | fence: nil}, {:fence_close, offset})

  defp scan_line({line, offset}, %{quote: %{} = block_quote} = state) do
    case quote_content(line, block_quote.base) do
      {:ok, content} -> %{state | quote: %{block_quote | lines: [content | block_quote.lines]}}
      :error -> scan_line({line, offset}, close_quote(state))
    end
  end

  defp scan_line({line, offset}, %{fence: nil} = state) do
    case measure(line, 0) do
      {_indent, ""} -> %{state | prev_paragraph?: false}
      {indent, rest} -> scan_block(offset, indent, rest, state)
    end
  end

  # A fence in a list item also ends with the item: a non-blank line indented less than
  # the item's content ends both, and is then scanned as a block of its own.
  defp scan_line({line, offset}, %{fence: {_char, _length, base}} = state) do
    {indent, rest} = measure(line, 0)

    cond do
      rest != "" and indent < base ->
        scan_line(
          {line, offset},
          state
          |> close_fence(offset)
          |> leaf()
        )

      fence_close?(indent, rest, state.fence) ->
        state
        |> close_fence(offset)
        |> leaf()

      true ->
        state
    end
  end

  # Leading whitespace width, with tabs advancing to the next multiple of 4.
  defp measure(" " <> rest, col), do: measure(rest, col + 1)
  defp measure("\t" <> rest, col), do: measure(rest, col + 4 - rem(col, 4))
  defp measure(rest, col), do: {col, rest}

  defp scan_block(offset, indent, rest, state) do
    if code_continues?(state.code, indent) do
      leaf(state)
    else
      container = Enum.drop_while(state.stack, &(&1 > indent))

      line = %{
        offset: offset,
        indent: indent,
        rel: indent - container_col(container),
        rest: rest,
        container: container
      }

      classify(line, %{state | code: nil})
    end
  end

  defp code_continues?(nil, _indent), do: false
  defp code_continues?(base, indent), do: indent >= base + 4

  defp container_col([]), do: 0
  defp container_col([col | _]), do: col

  # Four or more columns past the container is indented code, unless it follows paragraph
  # text: indented code cannot interrupt a paragraph, so the line is a lazy continuation.
  # CommonMark lets indented code follow a heading, fence or thematic break directly, so
  # this tests for paragraph text rather than for a preceding blank line.
  defp classify(%{rel: rel} = line, state) when rel >= 4 do
    if state.prev_paragraph? do
      paragraph(line, state)
    else
      indented_code(line, state)
    end
  end

  defp classify(line, state) do
    cond do
      String.starts_with?(line.rest, ">") -> open_quote(line, state)
      fence = fence_open(line.rest) -> open_fence(line, fence, state)
      thematic_break?(line.rest) -> leaf(%{state | stack: line.container})
      heading = atx_heading(line.rest) -> heading(line, heading, state)
      setext_underline?(line, state) -> setext(state)
      (item = list_item(line.rest)) && starts_item?(item, line, state) -> push_item(line, item, state)
      true -> paragraph(line, state)
    end
  end

  # Only top-level code and code inside a top-level list item is reported; deeper code is
  # still tracked so its lines are not scanned as blocks.
  defp indented_code(line, state) do
    state = leaf(%{state | stack: line.container, code: container_col(line.container)})

    if length(line.container) <= 1 do
      emit(state, {:indented_code, line.offset, line.rest})
    else
      state
    end
  end

  defp fence_open(rest) do
    case Regex.run(~r/^(`{3,}|~{3,})(.*)$/, rest) do
      [_, fence, info] -> fence_info(fence, String.trim(info))
      nil -> nil
    end
  end

  # A backtick in a backtick fence's info string makes the line an inline code span, not
  # a fence.
  defp fence_info("`" <> _ = fence, info) do
    if !String.contains?(info, "`") do
      {"`", String.length(fence), info}
    end
  end

  defp fence_info(fence, info), do: {"~", String.length(fence), info}

  defp open_fence(line, {char, length, info}, state) do
    %{state | stack: line.container, fence: {char, length, container_col(line.container)}}
    |> leaf()
    |> emit({:fence_open, line.offset, char, info})
  end

  defp fence_close?(indent, rest, {char, length, base}) do
    marker = String.trim_trailing(rest, " ")
    size = String.length(marker)

    indent <= base + 3 and size >= length and marker == String.duplicate(char, size)
  end

  defp thematic_break?(rest), do: Regex.match?(~r/^([-*_])( *\1){2,} *$/, rest)

  defp atx_heading(rest) do
    case Regex.run(~r/^(\#{1,6})(?:[ \t]+(.*)|$)/, rest, capture: :all_but_first) do
      [hashes] -> {String.length(hashes), ""}
      [hashes, text] -> {String.length(hashes), heading_text(text)}
      nil -> nil
    end
  end

  # Drops an optional closing sequence of `#`s, as CommonMark does.
  defp heading_text(text) do
    text
    |> String.trim()
    |> String.replace(~r/(^|[ \t]+)#+$/, "")
  end

  defp heading(line, {level, text}, state) do
    %{state | stack: line.container}
    |> leaf()
    |> emit({:heading, line.offset, level, :atx, text})
  end

  # `===` under paragraph text is a level-1 heading on the paragraph. A lazy continuation
  # line (one that would leave the list) cannot be an underline.
  defp setext_underline?(line, state) do
    state.prev_paragraph? and line.container == state.stack and Regex.match?(~r/^=+ *$/, line.rest)
  end

  defp setext(state) do
    state
    |> leaf()
    |> emit({:heading, state.para_start, 1, :setext, state.para_text})
  end

  defp open_quote(line, state) do
    block_quote = %{start: line.offset, base: container_col(line.container), lines: [strip_quote_marker(line.rest)]}
    leaf(%{state | stack: line.container, quote: block_quote})
  end

  defp quote_content(line, base) do
    case measure(line, 0) do
      {indent, ">" <> _ = rest} when indent <= base + 3 -> {:ok, strip_quote_marker(rest)}
      _other -> :error
    end
  end

  defp strip_quote_marker(">" <> " " <> rest), do: rest
  defp strip_quote_marker(">" <> rest), do: rest

  defp close_quote(%{quote: nil} = state), do: state

  defp close_quote(%{quote: block_quote} = state) do
    lines = Enum.reverse(block_quote.lines)

    state = emit(%{state | quote: nil}, {:quote_open, block_quote.start})

    lines
    |> Enum.join("\n")
    |> scan()
    |> Enum.reduce(state, &emit(&2, shift(&1, block_quote.start)))
    |> emit({:quote_close, block_quote.start + length(lines) - 1})
  end

  defp shift(event, by), do: put_elem(event, 1, elem(event, 1) + by)

  defp list_item(rest) do
    case Regex.run(~r/^([-+*])( +)(\S.*)?$/, rest) do
      [_, marker, spaces | content] ->
        {:bullet, marker, 1, String.length(spaces), content != []}

      nil ->
        ordered_item(rest)
    end
  end

  defp ordered_item(rest) do
    case Regex.run(~r/^(\d{1,9}[.)])( +)(\S.*)?$/, rest) do
      [_, marker, spaces | content] -> {:ordered, marker, String.length(marker), String.length(spaces), content != []}
      nil -> nil
    end
  end

  # CommonMark: the first item of a list may interrupt a paragraph only when it isn't empty
  # and, if ordered, starts at 1; otherwise the line continues the paragraph. A paragraph in
  # the same container as the item means the item would start a new list there; anywhere
  # else, the item continues an enclosing list.
  defp starts_item?(_item, _line, %{prev_paragraph?: false}), do: true
  defp starts_item?(_item, %{container: container}, %{stack: stack}) when container != stack, do: true
  defp starts_item?({:bullet, _marker, _width, _spaces, content?}, _line, _state), do: content?

  defp starts_item?({:ordered, marker, _width, _spaces, content?}, _line, _state) do
    content? and match?({1, _}, Integer.parse(marker))
  end

  defp push_item(line, {kind, marker, width, spaces, content?}, state) do
    content_col = line.indent + width + content_spaces(spaces, content?)
    parent_col = container_col(line.container)

    state = %{
      state
      | stack: [content_col | line.container],
        prev_paragraph?: content? and spaces <= 4,
        para_start: line.offset,
        para_text: ""
    }

    if kind == :bullet do
      emit(state, {:list_item, line.offset, line.indent, marker, content_col, parent_col})
    else
      state
    end
  end

  # CommonMark: an empty item, or one whose text starts with indented code (five or more
  # spaces), has its content one column after the marker.
  defp content_spaces(spaces, true) when spaces <= 4, do: spaces
  defp content_spaces(_spaces, _content?), do: 1

  # A non-item line right after paragraph text is a lazy continuation and stays in the
  # current list item even when it is indented less.
  defp paragraph(line, state) do
    {stack, para_start, para_text} =
      if state.prev_paragraph? do
        {state.stack, state.para_start, state.para_text}
      else
        {line.container, line.offset, line.rest}
      end

    %{state | stack: stack, para_start: para_start, para_text: para_text, prev_paragraph?: true}
  end

  defp leaf(state), do: %{state | prev_paragraph?: false}

  defp emit(state, event), do: %{state | events: [event | state.events]}
end
