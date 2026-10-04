defmodule ThreeSixes.RoomTest do
  use ExUnit.Case, async: true

  alias ThreeSixes.Room

  @host "guest:host"

  defp room, do: Room.new("KQXT", @host)

  defp enter!(room, person_id, nickname) do
    {:ok, room} = Room.enter(room, person_id, nickname)
    room
  end

  test "a person who enters a Nickname becomes a member, the Nickname trimmed" do
    room = room()
    refute Room.member?(room, "guest:dana")

    room = enter!(room, "guest:dana", "  Dana  ")

    assert Room.member?(room, "guest:dana")
    assert Room.view_for(room, "guest:dana").me == "Dana"
  end

  test "an empty or whitespace-only Nickname is blank" do
    assert Room.enter(room(), "guest:dana", "") == {:error, :blank}
    assert Room.enter(room(), "guest:dana", "   \t ") == {:error, :blank}
  end

  test "a Nickname is at most 16 characters, counted as the eye reads them" do
    assert {:ok, _} = Room.enter(room(), "guest:dana", String.duplicate("a", 16))
    assert Room.enter(room(), "guest:dana", String.duplicate("a", 17)) == {:error, :too_long}
    assert {:ok, _} = Room.enter(room(), "guest:dana", String.duplicate("é", 16))
    assert {:ok, _} = Room.enter(room(), "guest:dana", "  " <> String.duplicate("a", 16) <> "  ")
  end

  test "a Nickname taken regardless of case gets the next number as a suggestion" do
    room = enter!(room(), "guest:dana", "Dana")

    assert Room.enter(room, "guest:other", "dana") == {:taken, "Dana 2"}
    refute Room.member?(room, "guest:other")
  end

  test "when the numbered Nickname is taken too, the suggestion is the next number" do
    room =
      room()
      |> enter!("guest:dana", "Dana")
      |> enter!("guest:dana2", "dana 2")

    assert Room.enter(room, "guest:other", "DANA") == {:taken, "Dana 3"}
  end

  test "a suggestion for a long Nickname cuts the name so the whole fits 16 characters" do
    fifteen = "Alexandrovichka"
    sixteen = "Alexandrovichkas"
    room = room() |> enter!("guest:a", fifteen) |> enter!("guest:b", sixteen)

    assert Room.enter(room, "guest:c", fifteen) == {:taken, "Alexandrovichk 2"}
    assert Room.enter(room, "guest:c", sixteen) == {:taken, "Alexandrovichk 2"}
  end

  test "the cut drops the space it would leave before the number" do
    room = enter!(room(), "guest:a", "Dana Kowalska Jo")

    assert Room.enter(room, "guest:b", "dana kowalska jo") == {:taken, "Dana Kowalska 2"}
  end

  test "a member who enters again keeps their Nickname and nothing changes" do
    room = enter!(room(), "guest:dana", "Dana")

    assert Room.enter(room, "guest:dana", "Someone else") == {:ok, room}
    assert Room.enter(room, "guest:dana", "dana") == {:ok, room}
    assert Room.enter(room, "guest:dana", "") == {:ok, room}
  end

  test "a Room takes 30 people and the 31st is full" do
    room = Enum.reduce(1..30, room(), &enter!(&2, "guest:#{&1}", "Person #{&1}"))

    assert Room.enter(room, "guest:31", "Person 31") == {:error, :full}
    assert Room.enter(room, "guest:1", "Person 1") == {:ok, room}
  end

  test "the view lists people in join order, marking the Host and the viewer" do
    room =
      room()
      |> enter!("guest:timur", "Timur")
      |> enter!(@host, "Malika")
      |> enter!("guest:dana", "Dana")

    assert Room.view_for(room, "guest:dana") == %{
             code: "KQXT",
             people: [
               %{nickname: "Timur", host?: false, me?: false, n: 1},
               %{nickname: "Malika", host?: true, me?: false, n: 2},
               %{nickname: "Dana", host?: false, me?: true, n: 3}
             ],
             me: "Dana",
             host?: false
           }

    assert %{me: "Malika", host?: true} = Room.view_for(room, @host)
  end

  test "the Host is not listed until they enter a Nickname, but knows they are the Host" do
    room = enter!(room(), "guest:dana", "Dana")

    assert %{people: [%{nickname: "Dana"}], me: nil, host?: true} = Room.view_for(room, @host)

    assert %{people: [%{nickname: "Dana"}], me: nil, host?: false} =
             Room.view_for(room, "guest:visitor")
  end

  test "the view never carries a person id, because a Guest id is that person's identity" do
    ids = [@host, "guest:dana", "guest:timur"]
    room = room() |> enter!(@host, "Malika") |> enter!("guest:dana", "Dana")

    for viewer <- ids, id <- ids do
      refute inspect(Room.view_for(room, viewer)) =~ id
    end
  end
end
