defmodule ThreeSixes.CredoChecks.CaseOnBoolean do
  use Credo.Check,
    base_priority: :normal,
    category: :refactor,
    explanations: [
      check: """
      A `case` with exactly `true` and `false` clauses obscures a boolean
      decision. Use `if`/`else` so the branching intent is immediately clear.

          # bad
          case enabled? do
            true -> :enabled
            false -> :disabled
          end

          # good
          if enabled?, do: :enabled, else: :disabled
      """
    ]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:case, meta, [_subject, [do: clauses]]} = ast, issues, issue_meta)
       when is_list(clauses) do
    if boolean_clauses?(clauses) do
      issue =
        format_issue(issue_meta,
          message: "Use `if`/`else` instead of `case` with boolean clauses.",
          trigger: "case",
          line_no: meta[:line]
        )

      {ast, [issue | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp boolean_clauses?([first, second]) do
    [first, second]
    |> Enum.map(&clause_pattern/1)
    |> Enum.sort() == [false, true]
  end

  defp boolean_clauses?(_clauses), do: false

  defp clause_pattern({:->, _meta, [[pattern], _body]}) when pattern in [true, false],
    do: pattern

  defp clause_pattern(_clause), do: nil
end
