defmodule ThreeSixesWeb.LeaderboardLiveTest do
  use ThreeSixesWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ThreeSixes.Accounts
  alias ThreeSixes.Records

  @guest "guest:rival"

  describe "with a short Leaderboard" do
    setup %{conn: conn} do
      {dana_conn, dana} = sign_in(conn, "Dana")
      {timur_conn, timur} = sign_in(build_conn(), "Timur")
      {malika_conn, malika} = sign_in(build_conn(), "Malika")
      {aziz_conn, aziz} = sign_in(build_conn(), "Aziz")
      {sasha_conn, _sasha} = sign_in(build_conn(), "Sasha")

      play(timur, wins: 3, games: 3)
      play(dana, wins: 1, games: 2)
      play(malika, wins: 1, games: 2)
      play(aziz, wins: 0, games: 4)

      %{
        dana_conn: dana_conn,
        timur_conn: timur_conn,
        malika_conn: malika_conn,
        aziz_conn: aziz_conn,
        sasha_conn: sasha_conn
      }
    end

    test "anyone sees each Account's position, Nickname, Games and Wins, best first",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/leaderboard")

      assert has_element?(view, "h1", "Leaderboard")

      assert rows(view, "#leaderboard tbody tr") == [
               ["1st", "Timur", "3", "3"],
               ["2nd", "Dana", "2", "1"],
               ["2nd", "Malika", "2", "1"],
               ["4th", "Aziz", "4", "0"]
             ]

      refute has_element?(view, "#leaderboard", "rival")
    end

    test "the first three positions are circled, and a crown sits on 1st", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/leaderboard")

      for n <- 1..3 do
        assert has_element?(view, "#leaderboard tbody tr:nth-child(#{n}) .circled")
      end

      refute has_element?(view, "#leaderboard tbody tr:nth-child(4) .circled")
      assert has_element?(view, "#leaderboard tbody tr:nth-child(1) .crown")
      refute has_element?(view, "#leaderboard tbody tr:not(:nth-child(1)) .crown")
    end

    test "a viewer in the top fifty finds their own row marked, and no slip",
         %{malika_conn: malika, aziz_conn: aziz} do
      {:ok, malika_view, _html} = live(malika, ~p"/leaderboard")
      {:ok, aziz_view, _html} = live(aziz, ~p"/leaderboard")

      assert has_element?(malika_view, "#leaderboard tbody tr.is-me:nth-child(3)", "← you")
      assert length(select(malika_view, "#leaderboard tr.is-me")) == 1
      refute has_element?(malika_view, "#my-standing")

      assert has_element?(aziz_view, "#leaderboard tbody tr.is-me:nth-child(4)", "Aziz")
      refute has_element?(aziz_view, "#leaderboard tbody tr.is-me:nth-child(3)")
    end

    test "a Guest is asked on the slip to sign in, and comes back here", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/leaderboard")

      assert has_element?(
               view,
               ~s(#my-standing a[href="/signin?return_to=%2Fleaderboard"]),
               "Sign in to get on the Leaderboard"
             )

      refute has_element?(view, "#leaderboard tr.is-me")
    end

    test "a Guest gets no slip when there is no way to sign in", %{conn: conn} do
      google = Application.fetch_env!(:ueberauth, Ueberauth.Strategy.Google.OAuth)
      dev_login = Application.fetch_env!(:three_sixes, :dev_login_enabled)
      Application.put_env(:ueberauth, Ueberauth.Strategy.Google.OAuth, [])
      Application.put_env(:three_sixes, :dev_login_enabled, false)

      on_exit(fn ->
        Application.put_env(:ueberauth, Ueberauth.Strategy.Google.OAuth, google)
        Application.put_env(:three_sixes, :dev_login_enabled, dev_login)
      end)

      {:ok, view, _html} = live(conn, ~p"/leaderboard")

      refute has_element?(view, "#my-standing")
    end

    test "an Account with no finished Game is told how to get on", %{sasha_conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/leaderboard")

      assert has_element?(view, "#my-standing", "Finish a Game to get on the Leaderboard.")
      refute has_element?(view, "#my-standing a")
      refute has_element?(view, "#leaderboard tr.is-me")
    end

    test "every page header links to the Leaderboard", %{conn: conn, dana_conn: dana} do
      for {conn, path} <- [{conn, ~p"/"}, {dana, ~p"/account"}, {conn, ~p"/leaderboard"}] do
        {:ok, view, _html} = live(conn, path)
        assert has_element?(view, ~s(header.top nav a[href="/leaderboard"]), "Leaderboard")
      end
    end

    test "the landing page links to the Leaderboard", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ~s(main a[href="/leaderboard"]), "Leaderboard")
    end

    test "the Account page says where the Account stands, and links to the Leaderboard",
         %{dana_conn: dana, timur_conn: timur, sasha_conn: sasha} do
      {:ok, dana_view, _html} = live(dana, ~p"/account")
      {:ok, timur_view, _html} = live(timur, ~p"/account")
      {:ok, sasha_view, _html} = live(sasha, ~p"/account")

      assert has_element?(dana_view, ~s(#standing a[href="/leaderboard"]), "2nd")
      assert has_element?(dana_view, "#standing", "You're 2nd on the Leaderboard")
      assert has_element?(timur_view, "#standing", "You're 1st on the Leaderboard")
      refute has_element?(sasha_view, "#standing")
    end
  end

  describe "with more than fifty Accounts" do
    setup %{conn: conn} do
      ahead = for n <- 1..50, do: "account:#{account_id("P#{n}")}"
      record([@guest | ahead])

      {gus_conn, gus} = sign_in(conn, "Gus")
      play(gus, wins: 0, games: 2)

      %{gus_conn: gus_conn}
    end

    test "only the top fifty are listed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/leaderboard")

      assert length(select(view, "#leaderboard tbody tr")) == 50
      refute has_element?(view, "#leaderboard", "Gus")
    end

    test "a viewer below them finds their row, with its real position, on the slip",
         %{gus_conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/leaderboard")

      assert [["51st", name, "2", "0"]] = rows(view, "#my-standing tr.is-me")
      assert name =~ "Gus"
      assert has_element?(view, "#my-standing tr.is-me em", "← you")
      refute has_element?(view, "#leaderboard tbody tr.is-me")
    end

    test "the Account page gives the real position too", %{gus_conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/account")

      assert has_element?(view, "#standing", "You're 51st on the Leaderboard")
    end
  end

  defp rows(view, selector) do
    for row <- select(view, selector) do
      for cell <- LazyHTML.query(row, "td") do
        cell |> LazyHTML.text() |> String.split() |> Enum.join(" ")
      end
    end
  end

  defp select(view, selector) do
    view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.to_list()
  end

  defp play(person_id, wins: wins, games: games) do
    for game <- 1..games//1 do
      if game <= wins, do: record([person_id, @guest]), else: record([@guest, person_id])
    end
  end

  defp record(person_ids) do
    {:ok, _game} =
      Records.record_game(%{
        room_code: "KQXT",
        rounds: 1,
        finished_at: ~U[2026-10-02 20:00:00Z],
        placement:
          for {person_id, place} <- Enum.with_index(person_ids, 1) do
            %{person_id: person_id, nickname: person_id, place: place}
          end,
        checks: []
      })
  end

  defp account_id(name) do
    {:created, account} = Accounts.find_or_create_dev(name)
    account.id
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
