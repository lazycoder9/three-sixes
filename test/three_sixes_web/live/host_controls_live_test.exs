defmodule ThreeSixesWeb.HostControlsLiveTest do
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

  describe "removing a Player mid-Round" do
    test "Knocks them out, sends them home, and the Round is re-rolled with the next Player opening" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      start(timur, [[3], [5], [2]])
      press(timur, "Bid one five")

      assert has_element?(timur, "#seat-2 button[popovertarget=person-dialog-2]", "Dana")
      assert text(timur, "#person-dialog-2 h2") == "Dana"

      assert has_element?(
               timur,
               "#person-dialog-2 button[phx-click=make_host]",
               "Make Dana the Host"
             )

      assert has_element?(
               timur,
               "#person-dialog-2 button[phx-click=remove]",
               "Remove from the Room"
             )

      assert text(timur, "#person-dialog-2 small") ==
               "Removing a Player mid-Game Knocks them out and voids the Round. " <>
                 "Dana can come back with the Room code, as a Spectator."

      Scripted.script([[4], [6]])
      timur |> element("#person-dialog-2 button", "Remove from the Room") |> render_click()

      assert {"/", %{"info" => removed}} = assert_redirect(dana)

      assert removed ==
               "You were removed from Room #{code}. You can come back with the Room code."

      for view <- [timur, malika] do
        assert has_element?(view, "#seat-2.is-out", "out")
        refute has_element?(view, "#seat-2 button")
        assert count(view, "[id^=person-dialog-2]") == 0
      end

      assert text(timur, "#scrap") ==
               "Dana is out. The Round is voided. Malika opens the Round. 2 dice on the table"

      assert text(malika, "#scrap") ==
               "Dana is out. The Round is voided. You open the Round. 2 dice on the table"

      assert faces(timur) == [4]
      assert faces(malika) == [6]
      assert text(malika, "#my-page .my-page__head") == "You open. Make a Bid."
    end
  end

  describe "the removed person" do
    test "rejoins with the Room code as a Spectator, Knocked out, and the Host can still tap them" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      start(timur, [[3], [5], [2]])
      Scripted.script([[4], [6]])
      timur |> element("#person-dialog-2 button", "Remove from the Room") |> render_click()
      assert_redirect(dana)

      dana = visit(code, "dana")
      assert has_element?(dana, "#join-form")

      assert text(dana, "#removed") ==
               "You were removed from Room #{code}. You can come back with the Room code."

      enter(dana, "Dana")

      refute has_element?(dana, "#my-page")
      assert text(dana, "#watching") == "You're Knocked out. You're watching. Waiting for Malika."
      assert has_element?(dana, "#seat-2.is-out", "You")

      for view <- [timur, malika, dana] do
        assert text(view, "#spectators-chip") == "1 Spectator"
        view |> element("#spectators-chip") |> render_click()
      end

      assert items(timur, "#spectators li") == ["D Dana out"]
      assert items(malika, "#spectators li") == ["D Dana out"]
      assert items(dana, "#spectators li") == ["D You out"]

      assert has_element?(timur, "#spectators button[popovertarget=person-dialog-2]", "Dana")
      assert has_element?(timur, "#seat-2 button[popovertarget=person-dialog-2]")

      assert text(timur, "#person-dialog-2 small") ==
               "Dana can come back with the Room code, as a Spectator."
    end
  end

  describe "the Host leaving" do
    test "mid-Game asks first, then leaves: the role goes to someone connected and everyone sees who" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      start(timur, [[3], [5], [2]])

      assert has_element?(timur, "#room-menu button[popovertarget=leave-dialog]", "Leave Room")
      refute has_element?(timur, "#room-menu button[phx-click=leave]")
      assert text(timur, "#leave-dialog h2") == "Leave the Room?"

      assert text(timur, "#leave-dialog p") ==
               "You'll be Knocked out of this Game, and the Round in play is voided."

      assert has_element?(timur, "#leave-dialog button[popovertarget=room-menu]", "Stay")

      Scripted.script_seats(["guest:timur", "guest:malika", "guest:dana"])
      Scripted.script([[4], [6]])

      timur |> element("#leave-dialog button", "Leave Room") |> render_click()

      assert {"/", %{"info" => left}} = assert_redirect(timur)
      assert left == "You left Room #{code}."

      assert text(malika, "#flash-info p") == "You're the Host now."
      assert text(dana, "#flash-info p") == "Malika is the Host now."

      assert text(dana, "#scrap") ==
               "Timur is out. The Round is voided. You open the Round. 2 dice on the table"

      assert has_element?(malika, "#seat-1.is-out", "out")
      assert has_element?(malika, "#seat-2 button[popovertarget=person-dialog-2]")
      refute has_element?(dana, "[popovertarget^=person-dialog]")
    end

    test "during the reveal, the confirm and the Host dialog say only that they are Knocked out" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana Malika))
      start(timur, [[3], [5], [2]])
      press(timur, "Bid one five")
      dana |> element("#my-page .my-page__check") |> render_click()

      assert text(timur, "#leave-dialog p") == "You'll be Knocked out of this Game."

      assert text(timur, "#person-dialog-3 small") ==
               "Removing a Player mid-Game Knocks them out. " <>
                 "Malika can come back with the Room code, as a Spectator."
    end

    test "outside a Game leaves at once, and the Host tag moves in the lobby" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))

      refute has_element?(timur, "#room-menu [popovertarget=leave-dialog]")
      refute has_element?(timur, "#leave-dialog")
      Scripted.script_seats(["guest:timur", "guest:dana", "guest:malika"])

      timur |> element("#room-menu button", "Leave Room") |> render_click()

      assert {"/", %{"info" => left}} = assert_redirect(timur)
      assert left == "You left Room #{code}."

      assert text(dana, "#flash-info p") == "You're the Host now."
      assert text(malika, "#flash-info p") == "Dana is the Host now."

      for view <- [dana, malika] do
        refute has_element?(view, "#person-1")
        assert has_element?(view, "#person-2 .host-tag")
      end

      assert has_element?(dana, "#lobby button[phx-click=start]", "Start Game")
      assert text(malika, "#lobby .lobby__wait") == "Waiting for Dana to start the Game."
    end
  end

  describe "handing over the Host role" do
    test "makes the person the Host, the old Host a person like any other, and everyone is told" do
      %{timur: timur, dana: dana, malika: malika} = table(~w(Timur Dana Malika))

      assert text(timur, "#person-dialog-2 small") == "Dana can come back with the Room code."

      timur |> element("#person-dialog-2 button", "Make Dana the Host") |> render_click()

      assert text(dana, "#flash-info p") == "You're the Host now."
      assert text(timur, "#flash-info p") == "Dana is the Host now."
      assert text(malika, "#flash-info p") == "Dana is the Host now."

      assert has_element?(dana, "#lobby button[phx-click=start]", "Start Game")
      refute has_element?(timur, "#lobby button[phx-click=start]")
      assert text(timur, "#lobby .lobby__wait") == "Waiting for Dana to start the Game."

      for view <- [timur, malika] do
        assert has_element?(view, "#person-2 .host-tag")
        refute has_element?(view, "#person-1 .host-tag")
      end

      refute has_element?(timur, "[popovertarget^=person-dialog]")
      refute has_element?(timur, "[id^=person-dialog]")
      assert has_element?(dana, "#person-1 button[popovertarget=person-dialog-1]", "Timur")
      assert text(dana, "#person-dialog-1 h2") == "Timur"
    end
  end

  describe "a Spectator leaving mid-Game" do
    test "leaves at once with no confirm, and the Game carries on as it was" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      tick_sit_out(malika, true)
      start(timur, [[3], [5]])
      press(timur, "Bid one five")

      refute has_element?(malika, "#room-menu [popovertarget=leave-dialog]")
      refute has_element?(malika, "#leave-dialog")
      assert has_element?(timur, "#room-menu [popovertarget=leave-dialog]")

      malika |> element("#room-menu button", "Leave Room") |> render_click()

      assert {"/", %{"info" => left}} = assert_redirect(malika)
      assert left == "You left Room #{code}."

      for view <- [timur, dana], do: refute(has_element?(view, "#spectators-chip"))
      assert text(timur, "#scrap") == "You bid 1 × 2 dice on the table"
      assert text(dana, "#scrap") == "Timur bids 1 × 2 dice on the table"

      assert text(dana, "#my-page .my-page__head") == "Your turn. Raise it, or Check it."
    end
  end

  describe "a person dialog event" do
    test "with a number that is not a whole number, or from a non-Host, changes nothing" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana Malika))

      for event <- ~w(remove make_host), n <- ["two", "2.5", "", "0", "-1", "9"] do
        render_click(timur, event, %{"n" => n})
      end

      render_click(dana, "remove", %{"n" => "3"})
      render_click(dana, "make_host", %{"n" => "2"})

      for view <- [timur, dana] do
        assert items(view, "#people li") |> length() == 3
        assert has_element?(view, "#person-1 .host-tag")
        refute has_element?(view, "#flash-info")
      end
    end
  end

  describe "a non-Host" do
    test "has no person to tap and no dialog, in the lobby, at the table and in the Spectators" do
      %{timur: timur, dana: dana, malika: malika} = table(~w(Timur Dana Malika))
      tick_sit_out(malika, true)

      assert has_element?(timur, "#person-2 button[popovertarget=person-dialog-2]")

      for view <- [dana, malika] do
        refute has_element?(view, "[popovertarget^=person-dialog]")
        refute has_element?(view, "[id^=person-dialog]")
      end

      start(timur, [[3], [5]])
      for view <- [dana, malika], do: view |> element("#spectators-chip") |> render_click()

      assert has_element?(timur, "#seat-2 button[popovertarget=person-dialog-2]")
      assert items(dana, "#spectators li") == ["M Malika"]
      assert items(malika, "#spectators li") == ["M You"]

      for view <- [dana, malika] do
        refute has_element?(view, "[popovertarget^=person-dialog]")
        refute has_element?(view, "[id^=person-dialog]")
      end
    end
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

  defp start(host, rolls) do
    Scripted.script(rolls)
    host |> element("#lobby button", "Start Game") |> render_click()
  end

  defp tick_sit_out(view, ticked?) do
    view |> form("#sit-out-form", %{sitting_out: to_string(ticked?)}) |> render_change()
  end

  defp items(view, selector) do
    view
    |> render()
    |> String.replace("<", " <")
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.split() |> Enum.join(" ")))
  end

  defp text(view, selector) do
    view
    |> render()
    |> String.replace("<", " <")
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.text()
    |> String.split()
    |> Enum.join(" ")
  end

  defp press(view, label),
    do: view |> element("#my-page button[aria-label='#{label}']") |> render_click()

  defp faces(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#my-dice [data-face]")
    |> LazyHTML.attribute("data-face")
    |> Enum.map(&String.to_integer/1)
  end

  defp count(view, selector) do
    view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()
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
