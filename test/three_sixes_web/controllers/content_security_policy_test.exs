defmodule ThreeSixesWeb.ContentSecurityPolicyTest do
  use ThreeSixesWeb.ConnCase

  test "the policy allows the page's inline theme script and no other inline script", %{
    conn: conn
  } do
    conn = get(conn, ~p"/")
    [policy] = get_resp_header(conn, "content-security-policy")

    [script] =
      conn
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query("script:not([src])")
      |> Enum.map(&LazyHTML.text/1)

    hash = Base.encode64(:crypto.hash(:sha256, script))
    assert policy =~ ~r/script-src 'self' 'sha256-#{Regex.escape(hash)}';/
  end
end
