defmodule ThreeSixes.RecordsTest do
  use ThreeSixes.DataCase, async: false

  alias ThreeSixes.Records
  alias ThreeSixes.Records.GameRecord

  @game %{
    room_code: "KQXT",
    rounds: 7,
    placement: [
      %{person_id: "guest:dana", nickname: "Dana", place: 1},
      %{person_id: "account:4", nickname: "Malika", place: 2}
    ],
    checks: [
      %{round: 2, checker: "guest:dana", bidder: "account:4", stood?: false},
      %{round: 5, checker: "account:4", bidder: "guest:dana", stood?: true}
    ]
  }

  test "a finished Game is stored with its Placements and its Checks" do
    assert {:ok, %GameRecord{id: id}} = Records.record_game(@game)

    record = GameRecord |> Repo.get!(id) |> Repo.preload([:placements, :checks])

    assert %{room_code: "KQXT", rounds: 7, finished_at: %DateTime{}} = record

    assert record.placements |> Enum.map(&{&1.person_id, &1.nickname, &1.place}) |> Enum.sort() ==
             [{"account:4", "Malika", 2}, {"guest:dana", "Dana", 1}]

    assert record.checks
           |> Enum.map(&{&1.round, &1.checker_id, &1.bidder_id, &1.stood})
           |> Enum.sort() ==
             [{2, "guest:dana", "account:4", false}, {5, "account:4", "guest:dana", true}]
  end

  test "a Game with a Placement that cannot be stored stores nothing" do
    broken = put_in(@game.placement, [%{person_id: "guest:dana", nickname: nil, place: 1}])

    assert {:error, _changeset} = Records.record_game(broken)
    assert Repo.aggregate(GameRecord, :count) == 0
  end
end
