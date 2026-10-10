defmodule ThreeSixesWeb.AccountLiveTest do
  use ThreeSixesWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ThreeSixes.Accounts
  alias ThreeSixes.Records

  setup %{conn: conn} do
    {dana_conn, dana} = sign_in(conn, "Dana")
    {timur_conn, timur} = sign_in(build_conn(), "Timur")

    malika = "guest:malika"
    aziz = "guest:aziz"
    kamila = "guest:kamila"
    other_dana = "guest:dana-phone"

    record(
      ~U[2026-09-19 12:00:00Z],
      [{malika, "Malika"}, {aziz, "Aziz"}, {timur, "Timur"}, {dana, "Dana"}],
      [
        {dana, malika, true},
        {timur, dana, false}
      ]
    )

    record(~U[2026-10-02 20:30:00Z], [{dana, "Dana"}, {timur, "Timur"}, {malika, "Malika"}], [
      {dana, timur, false},
      {timur, dana, true}
    ])

    record(~U[2026-09-26 09:00:00Z], [{timur, "Timur"}, {dana, "Dana 2"}, {other_dana, "Dana"}], [
      {timur, dana, false}
    ])

    record(~U[2026-09-30 23:59:00Z], [{dana, "Dana"}, {aziz, "Aziz"}], [
      {aziz, dana, false},
      {dana, aziz, false}
    ])

    record(
      ~U[2026-10-01 18:00:00Z],
      [{aziz, "Aziz"}, {kamila, "Kamila"}, {dana, "Dana"}, {malika, "Malika"}],
      [{dana, aziz, false}, {dana, malika, false}]
    )

    record(~U[2026-10-03 10:00:00Z], [{malika, "Malika"}, {timur, "Timur"}], [
      {timur, malika, false},
      {malika, timur, false}
    ])

    %{dana_conn: dana_conn, timur_conn: timur_conn}
  end

  test "the score sheet shows the six stats, with wins as tally marks", %{dana_conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/account")

    assert has_element?(view, ".paper h2", "The score so far")
    assert_stat(view, "Games", "5")
    assert_stat(view, "Wins", "2")
    assert_stat(view, "Win rate", "40%")
    assert_stat(view, "Average Placement", "2.2")
    assert_stat(view, "Checks won", "4")
    assert_stat(view, "Bluffs caught", "3")
    assert has_element?(view, ~s(dl.score dd .tally[aria-hidden="true"]))
  end

  test "Recent Games lists my Games newest first, with the date, my Placement and the full Placement list",
       %{dana_conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/account")

    assert has_element?(view, ".paper h2", "Recent Games")

    for {date, text, n} <- [
          {"2026-10-02", "Oct 2", 1},
          {"2026-10-01", "Oct 1", 2},
          {"2026-09-30", "Sep 30", 3},
          {"2026-09-26", "Sep 26", 4},
          {"2026-09-19", "Sep 19", 5}
        ] do
      assert has_element?(view, ~s|ol.games > li:nth-child(#{n}) time[datetime="#{date}"]|, text)
    end

    refute has_element?(view, "ol.games > li:nth-child(6)")

    assert has_element?(view, "ol.games > li:nth-child(1) .rank .circled", "1st")
    assert has_element?(view, "ol.games > li:nth-child(1) .rank", "of 3")
    assert has_element?(view, "ol.games > li:nth-child(2) .rank", "3rd")
    assert has_element?(view, "ol.games > li:nth-child(2) .rank", "of 4")
    refute has_element?(view, "ol.games > li:nth-child(2) .circled")
    assert has_element?(view, "ol.games > li:nth-child(5) .rank", "4th")

    for {name, n} <- Enum.with_index(["Dana", "Timur", "Malika"], 1) do
      assert has_element?(
               view,
               "ol.games > li:nth-child(1) .order > span:nth-child(#{n})",
               "#{n}. #{name}"
             )
    end

    assert has_element?(view, "ol.games > li:nth-child(1) .order > span:nth-child(1) .hl", "Dana")
    refute has_element?(view, "ol.games > li:nth-child(1) .order > span:not(:nth-child(1)) .hl")
  end

  test "only my seat is highlighted, under the Nickname I used", %{dana_conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/account")

    sep_26 = "ol.games > li:nth-child(4)"
    assert has_element?(view, "#{sep_26} .rank", "2nd")
    assert has_element?(view, "#{sep_26} .order > span:nth-child(2) .hl", "Dana 2")
    assert has_element?(view, "#{sep_26} .order > span:nth-child(3)", "3. Dana")
    refute has_element?(view, "#{sep_26} .order > span:not(:nth-child(2)) .hl")
  end

  test "each Account sees only its own stats and Games", %{dana_conn: dana, timur_conn: timur} do
    {:ok, dana_view, _html} = live(dana, ~p"/account")
    {:ok, timur_view, _html} = live(timur, ~p"/account")

    assert_stat(timur_view, "Games", "4")
    assert_stat(timur_view, "Wins", "1")
    assert_stat(timur_view, "Win rate", "25%")
    assert_stat(timur_view, "Average Placement", "2.0")
    assert_stat(timur_view, "Checks won", "3")
    assert_stat(timur_view, "Bluffs caught", "2")

    assert has_element?(timur_view, ~s|ol.games > li:nth-child(1) time[datetime="2026-10-03"]|)

    assert has_element?(
             timur_view,
             "ol.games > li:nth-child(1) .order > span:nth-child(2) .hl",
             "Timur"
           )

    refute has_element?(timur_view, "ol.games > li:nth-child(5)")

    refute has_element?(dana_view, ~s(time[datetime="2026-10-03"]))
    assert_stat(dana_view, "Games", "5")
  end

  test "with no Games the score sheet shows zeros and dashes, and Recent Games says when it fills in" do
    {conn, _sasha} = sign_in(build_conn(), "Sasha")

    {:ok, view, _html} = live(conn, ~p"/account")

    assert_stat(view, "Games", "0")
    assert_stat(view, "Wins", "0")
    assert_stat(view, "Win rate", "–")
    assert_stat(view, "Average Placement", "–")
    assert_stat(view, "Checks won", "0")
    assert_stat(view, "Bluffs caught", "0")
    refute has_element?(view, ".tally")

    refute has_element?(view, "ol.games")
    assert has_element?(view, ".paper p", "This list fills in after your first finished Game.")
  end

  defp assert_stat(view, term, value) do
    row = ~r/^\s*#{Regex.escape(term)}\s*#{Regex.escape(value)}\s*$/
    assert has_element?(view, "dl.score > div", row), "expected #{term} to read #{value}"
  end

  defp record(finished_at, players, checks) do
    {:ok, _game} =
      Records.record_game(%{
        room_code: "KQXT",
        rounds: max(length(checks), 1),
        finished_at: finished_at,
        placement:
          for {{person_id, nickname}, place} <- Enum.with_index(players, 1) do
            %{person_id: person_id, nickname: nickname, place: place}
          end,
        checks:
          for {{checker, bidder, stood?}, round} <- Enum.with_index(checks, 1) do
            %{round: round, checker: checker, bidder: bidder, stood?: stood?}
          end
      })
  end

  defp sign_in(conn, name) do
    conn =
      conn
      |> init_test_session(%{"guest_id" => String.downcase(name)})
      |> post(~p"/auth/dev", %{name: name})

    account = Accounts.get_account(get_session(conn, "account_id"))
    {recycle(conn), Accounts.person_id(account)}
  end
end
