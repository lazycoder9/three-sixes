defmodule ThreeSixes.Records.GameRecord do
  use Ecto.Schema

  import Ecto.Changeset

  alias ThreeSixes.Records.CheckRecord
  alias ThreeSixes.Records.Placement

  @type t :: %__MODULE__{}

  schema "game_records" do
    field :room_code, :string
    field :rounds, :integer
    field :finished_at, :utc_datetime_usec

    has_many :placements, Placement
    has_many :checks, CheckRecord
  end

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:room_code, :rounds, :finished_at])
    |> validate_required([:room_code, :rounds, :finished_at])
    |> cast_assoc(:placements, with: &Placement.changeset/2, required: true)
    |> cast_assoc(:checks, with: &CheckRecord.changeset/2)
  end
end
