defmodule ThreeSixes.CredoChecks.RawInHeex do
  @moduledoc "Kept outside `lib/` because Credo is not a runtime dependency."

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      `raw/1` marks content as safe HTML and bypasses HEEx escaping. Prefer
      escaped content. When sanitized HTML is intentional, place a
      `credo:allow-raw` HEEx comment on the same or immediately preceding line.
      """
    ]

  @allow_marker "credo:allow-raw"
  @raw_call ~r/(?:\{[^{}]*|<%=?(?:(?!%>).)*)\braw\s*\(/s

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:sigil_H, meta, [{:<<>>, _, parts}, _modifiers]} = ast, issues, issue_meta) do
    template = parts |> Enum.filter(&is_binary/1) |> Enum.join()
    {ast, issues_for_template(template, meta[:line], issue_meta) ++ issues}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issues_for_template(template, sigil_line, issue_meta) do
    lines = String.split(template, "\n")

    @raw_call
    |> Regex.scan(template, return: :index)
    |> Enum.map(fn [{start, length} | _captures] ->
      line_index(template, start + length - 1)
    end)
    |> Enum.uniq()
    |> Enum.reject(&allowed?(lines, &1))
    |> Enum.map(&issue_for(issue_meta, sigil_line + 1 + &1))
  end

  defp line_index(template, byte_offset) do
    template
    |> binary_part(0, byte_offset)
    |> :binary.matches("\n")
    |> length()
  end

  defp allowed?(lines, index) do
    current = Enum.at(lines, index, "")
    previous = if index > 0, do: Enum.at(lines, index - 1, ""), else: ""

    String.contains?(current, @allow_marker) or String.contains?(previous, @allow_marker)
  end

  defp issue_for(issue_meta, line_no) do
    format_issue(issue_meta,
      message:
        "Avoid `raw/1` in HEEx; sanitize deliberately and add `credo:allow-raw` to opt out.",
      trigger: "raw",
      line_no: line_no
    )
  end
end
