defmodule SfoxCredo.Check.Docs do
  @moduledoc false

  # Extracts literal `@moduledoc`, `@doc` and `@typedoc` text from a source file, with
  # enough position information to map a 0-based line offset in the text back to a source
  # line.

  alias Credo.SourceFile
  alias SfoxCredo.Check.Docs.Markdown

  @attributes [:moduledoc, :doc, :typedoc]
  @heredoc_delimiters [~s("""), ~s(''')]

  @type t :: %{
          attribute: :moduledoc | :doc | :typedoc,
          text: String.t(),
          line: pos_integer(),
          heredoc?: boolean()
        }

  @doc false
  @spec extract(SourceFile.t()) :: [t()]
  def extract(source_file) do
    lines =
      source_file
      |> SourceFile.lines()
      |> Map.new()

    {_ast, docs} =
      source_file
      |> SourceFile.ast()
      |> Macro.prewalk([], &collect(&1, &2, lines))

    Enum.reverse(docs)
  end

  @doc false
  @spec line_no(t(), non_neg_integer()) :: pos_integer()
  def line_no(%{heredoc?: true, line: line}, offset), do: line + 1 + offset
  def line_no(%{line: line}, _offset), do: line

  defp collect({:@, meta, [{attribute, _, [value]}]} = node, acc, lines) when attribute in @attributes do
    case doc_for(value, Keyword.get(meta, :line), lines) do
      nil -> {node, acc}
      {text, line, heredoc?} -> {node, [%{attribute: attribute, text: text, line: line, heredoc?: heredoc?} | acc]}
    end
  end

  defp collect(node, acc, _lines), do: {node, acc}

  defp doc_for(value, line, lines) when is_binary(value), do: plain_doc(value, line, lines)
  defp doc_for({:<<>>, _, parts}, line, lines) when is_list(parts), do: plain_doc(join_parts(parts), line, lines)

  # Sigils keep their delimiter in the AST metadata, so they don't need the source line
  # test.
  defp doc_for({sigil, meta, [{:<<>>, _, parts}, _modifiers]}, _line, _lines) when sigil in [:sigil_S, :sigil_s] do
    {join_parts(parts), Keyword.get(meta, :line), Keyword.get(meta, :delimiter) in @heredoc_delimiters}
  end

  defp doc_for(_value, _line, _lines), do: nil

  defp plain_doc(text, line, lines) do
    if heredoc_line?(lines, line) do
      {source_aligned(text, line, lines), line, true}
    else
      {text, line, false}
    end
  end

  # Credo parses without `literal_encoder`, so a plain string carries no delimiter
  # metadata. A heredoc opens at the end of the attribute's line.
  defp heredoc_line?(lines, line) do
    lines
    |> Map.get(line, "")
    |> String.trim_trailing()
    |> String.ends_with?(~s("""))
  end

  # Escapes (`\n`, a trailing `\`) and multi-line interpolations change the number of
  # lines in a heredoc's value, so offsets into it no longer map to source lines. When
  # they would drift, the heredoc's source lines (dedented by the closing delimiter's
  # indentation) are scanned instead.
  defp source_aligned(text, line, lines) do
    value_lines = length(Markdown.lines(text))

    case heredoc_body(lines, line + 1, []) do
      {body, indent} when length(body) + 1 != value_lines -> Enum.map_join(body, "\n", &dedent(&1, indent)) <> "\n"
      _aligned_or_unclosed -> text
    end
  end

  # The source lines up to the closing `"""`, and the closing delimiter's indentation.
  defp heredoc_body(lines, line, acc) do
    case Map.fetch(lines, line) do
      {:ok, source} ->
        trimmed = String.trim_leading(source)

        if String.starts_with?(trimmed, ~s(""")) do
          {Enum.reverse(acc), byte_size(source) - byte_size(trimmed)}
        else
          heredoc_body(lines, line + 1, [source | acc])
        end

      # coveralls-ignore-next-line
      :error ->
        nil
    end
  end

  defp dedent(line, indent) do
    {leading, rest} = String.split_at(line, indent)

    if String.trim(leading) == "" do
      rest
    else
      String.trim_leading(line)
    end
  end

  defp join_parts(parts) do
    Enum.map_join(parts, fn
      part when is_binary(part) -> part
      _interpolation -> "\x00"
    end)
  end
end
