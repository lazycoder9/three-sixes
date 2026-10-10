defmodule ThreeSixesWeb.ReactionLiveTest do
  use ThreeSixesWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ThreeSixes.Dice.Scripted
  alias ThreeSixes.Rooms

  setup do
    on_exit(fn ->
      for {_id, pid, _type, _modules} <-
            DynamicSupervisor.which_children(ThreeSixes.Rooms.Supervisor),
          do: DynamicSupervisor.terminate_child(ThreeSixes.Rooms.Supervisor, pid)
    end)
  end

  describe "in the lobby" do
    test "another person sees a Reaction beside the sender's name" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana))

      react(dana, "GG")

      assert has_element?(
               timur,
               "#person-2 .reaction.reaction--side[aria-label='Dana: GG']",
               "GG"
             )

      assert has_element?(dana, "#person-2 .reaction[aria-label='You: GG']", "GG")
      refute has_element?(timur, "#person-1 .reaction")
    end

    test "a react outside the set, or with junk params, shows nothing and leaves the note alone" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))

      for params <- [%{"reaction" => "wave"}, %{"reaction" => ["gg"]}, %{}],
          do: render_click(dana, "react", params)

      refute has_element?(timur, ".reaction")
      refute has_element?(dana, "#reactions.is-cooling")
      assert Rooms.whereis(code)
    end
  end

  describe "the wait" do
    test "a second one within 2 seconds is ignored, and only the sender's note greys out" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana))
      start(timur, [[2], [5]])

      react(dana, "GG")
      react(dana, "No way")

      assert has_element?(timur, "#seat-2 .reaction[aria-label='Dana: GG']", "GG")
      assert count(timur, ".reaction") == 1
      assert has_element?(dana, "#my-page .reaction[aria-label='You: GG']")
      assert count(dana, ".reaction") == 1

      assert has_element?(dana, "#reactions.is-cooling")
      assert count(dana, "#reactions button[aria-disabled=true]") == 8
      refute has_element?(timur, "#reactions.is-cooling")
      refute has_element?(timur, "#reactions button[aria-disabled]")
    end

    test "the note comes back when the wait is over, and the next Reaction replaces the first" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      react(dana, "GG")
      [first] = ids(timur, ".reaction")

      send(dana.pid, {:reaction_wait_over, make_ref()})

      assert has_element?(dana, "#reactions.is-cooling")

      end_wait(dana)

      refute has_element?(dana, "#reactions.is-cooling")
      refute has_element?(dana, "#reactions button[aria-disabled]")

      send(Rooms.whereis(code), {:reaction_ready, "guest:dana"})
      react(dana, "Fire")

      assert has_element?(timur, "#person-2 .reaction[aria-label='Dana: Fire']", "🔥")
      assert [second] = ids(timur, ".reaction")
      assert second != first
      assert has_element?(dana, "#reactions.is-cooling")
    end
  end

  describe "the pop-up" do
    test "goes on its timer, and the timer of one it replaced leaves the new one up" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      react(dana, "GG")
      first = popup_timer(timur)
      send(Rooms.whereis(code), {:reaction_ready, "guest:dana"})
      react(dana, "Check it!")

      send(timur.pid, first)

      assert has_element?(timur, "#person-2 .reaction[aria-label='Dana: Check it!']", "Check it!")

      send(timur.pid, popup_timer(timur))
      send(dana.pid, popup_timer(dana))

      refute has_element?(timur, ".reaction")
      refute has_element?(dana, ".reaction")
    end
  end

  describe "at the table" do
    test "another Player sees it over the sender's seat, and the sender over their own page" do
      %{timur: timur, dana: dana, malika: malika} = table(~w(Timur Dana Malika))
      start(timur, [[2], [5], [4]])

      react(dana, "Laugh")

      for other <- [timur, malika] do
        assert has_element?(other, "#seat-2 .reaction[aria-label='Dana: Laugh']", "😂")
      end

      assert has_element?(dana, "#my-page .reaction[aria-label='You: Laugh']", "😂")
      assert count(timur, ".reaction") == 1
      assert count(dana, ".reaction") == 1
    end

    test "one sent during the reveal shows over the sender's seat" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      start(timur, [[2], [5]])
      press(timur, "Bid one five")
      check(dana)
      reveal(code, {:reveal, 1, 1})

      react(timur, "Gasp")

      assert has_element?(dana, "#seat-1 .reaction[aria-label='Timur: Gasp']", "😱")
      assert has_element?(timur, "#my-page .reaction[aria-label='You: Gasp']")
    end

    test "a Knocked-out Player's pops over their seat, which still shows, not by the chip" do
      %{timur: timur, dana: dana, code: code} = players = table(~w(Timur Dana Malika))
      timur_takes_his_sixth_die(players)
      next_round(code, 5, [[2], [3]])

      react(timur, "Clap")

      assert has_element?(dana, "#seat-1.is-out .reaction[aria-label='Timur: Clap']", "👏")
      assert has_element?(timur, "#seat-1 .reaction[aria-label='You: Clap']")
      refute has_element?(dana, ".spec__reactions .reaction")
    end
  end

  describe "at Game over" do
    test "it pops beside the sender's name under the Placement" do
      %{timur: timur, dana: dana, code: code} = players = table(~w(Timur Dana))
      timur_takes_his_sixth_die(players)
      reveal(code, {:next_round, 5})

      react(timur, "GG")

      assert has_element?(dana, "#placement")
      assert has_element?(dana, "#person-1 .reaction--side[aria-label='Timur: GG']", "GG")
      assert has_element?(timur, "#person-1 .reaction[aria-label='You: GG']")
    end
  end

  test "the note is there in the lobby, for a Player and for a Spectator, but not before a Nickname" do
    %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
    aziz = visit(code, "aziz")

    assert note(timur) == ["Laugh", "Gasp", "Hmm", "Clap", "Fire", "GG", "No way", "Check it!"]
    refute has_element?(aziz, "#reactions")

    start(timur, [[2], [5]])
    enter(aziz, "Aziz")

    for view <- [timur, dana, aziz], do: assert(note(view) == note(timur))
    assert has_element?(aziz, "#watching")

    assert has_element?(
             timur,
             "#reactions[role=group][aria-label='Send a Reaction'] button[phx-click=react][phx-value-reaction=lol]",
             "😂"
           )
  end

  describe "from a Spectator" do
    test "pops beside the Spectators chip while the list is closed, and beside their name when open" do
      %{timur: timur, dana: dana, malika: malika} = table(~w(Timur Dana Malika))
      tick_sit_out(malika, true)
      start(timur, [[2], [5]])
      dana |> element("#spectators-chip") |> render_click()

      react(malika, "Hmm")

      assert has_element?(
               timur,
               "#spectators-chip + .spec__reactions > .reaction--side[aria-label='Malika: Hmm']",
               "🤨"
             )

      refute has_element?(timur, "#spectators .reaction")
      assert has_element?(dana, "#spectator-3 .reaction--side[aria-label='Malika: Hmm']", "🤨")
      refute has_element?(dana, ".spec__reactions .reaction")

      assert has_element?(
               malika,
               "#spectators-chip + .spec__reactions > .reaction[aria-label='You: Hmm']"
             )

      assert count(timur, ".reaction") == 1
    end
  end

  defp react(view, label),
    do: view |> element("#reactions button[aria-label='#{label}']") |> render_click()

  defp note(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#reactions button")
    |> LazyHTML.attribute("aria-label")
  end

  defp timur_takes_his_sixth_die(%{timur: timur, dana: dana, code: code} = players) do
    others = List.duplicate([2], map_size(players) - 2)
    start(timur, [[1] | others])

    for round <- 1..4 do
      bluff_caught(code, timur, dana, round)
      next_round(code, round, [List.duplicate(1, round + 1) | others])
    end

    bluff_caught(code, timur, dana, 5)
  end

  defp bluff_caught(code, bidder, checker, round) do
    press(bidder, "Bid one six")
    check(checker)
    for step <- 1..3, do: reveal(code, {:reveal, round, step})
  end

  defp next_round(code, round, rolls) do
    Scripted.script(rolls)
    reveal(code, {:next_round, round})
  end

  defp reveal(code, message) do
    pid = Rooms.whereis(code)
    send(pid, message)
    :sys.get_state(pid)
  end

  defp press(view, label),
    do: view |> element("#my-page button[aria-label='#{label}']") |> render_click()

  defp check(view), do: view |> element("#my-page button", "Check") |> render_click()

  defp tick_sit_out(view, ticked?) do
    view |> form("#sit-out-form", %{sitting_out: to_string(ticked?)}) |> render_change()
  end

  defp start(host, rolls) do
    Scripted.script(rolls)
    host |> element("#lobby button", "Start Game") |> render_click()
  end

  defp end_wait(view) do
    %{socket: %{assigns: %{reaction_wait: wait}}} = :sys.get_state(view.pid)
    send(view.pid, {:reaction_wait_over, wait})
  end

  defp popup_timer(view) do
    [id] = ids(view, ".reaction")
    ["reaction", n, id] = String.split(id, "-")
    {:reaction_over, String.to_integer(n), String.to_integer(id)}
  end

  defp ids(view, selector) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute("id")
  end

  defp count(view, selector) do
    view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()
  end

  defp table(nicknames) do
    {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")

    nicknames
    |> Map.new(fn nickname ->
      id = String.downcase(nickname)
      view = visit(code, id)
      enter(view, nickname)
      {String.to_existing_atom(id), view}
    end)
    |> Map.put(:code, code)
  end

  defp visit(code, guest_id) do
    {:ok, view, _html} =
      build_conn() |> init_test_session(%{"guest_id" => guest_id}) |> live(~p"/r/#{code}")

    view
  end

  defp enter(view, nickname) do
    view |> form("#join-form", %{nickname: nickname}) |> render_submit()
  end
end
