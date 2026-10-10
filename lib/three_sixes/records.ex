defmodule ThreeSixes.Records do
  alias ThreeSixes.Game
  alias ThreeSixes.Records.GameRecord
  alias ThreeSixes.Repo
  alias ThreeSixes.Room

  @type game :: %{
          required(:room_code) => String.t(),
          required(:rounds) => pos_integer(),
          required(:placement) => [
            %{person_id: Room.person_id(), nickname: String.t(), place: pos_integer()}
          ],
          required(:checks) => [Game.check()],
          optional(:finished_at) => DateTime.t()
        }

  @spec record_game(game()) ::
          {:ok, GameRecord.t()} | {:error, Ecto.Changeset.t()}
  def record_game(game) do
    %{
      room_code: game.room_code,
      rounds: game.rounds,
      finished_at: Map.get_lazy(game, :finished_at, &DateTime.utc_now/0),
      placements: game.placement,
      checks:
        for check <- game.checks do
          %{
            round: check.round,
            checker_id: check.checker,
            bidder_id: check.bidder,
            stood: check.stood?
          }
        end
    }
    |> GameRecord.changeset()
    |> Repo.insert()
  end
end
