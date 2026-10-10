defmodule ThreeSixes.Records.Placement do
  use Ecto.Schema

  import Ecto.Changeset

  alias ThreeSixes.Records.GameRecord

  @type t :: %__MODULE__{}

  schema "placements" do
    belongs_to :game_record, GameRecord
    field :person_id, :string
    field :nickname, :string
    field :place, :integer
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(placement, attrs) do
    placement
    |> cast(attrs, [:person_id, :nickname, :place])
    |> validate_required([:person_id, :nickname, :place])
    |> unique_constraint([:game_record_id, :person_id])
  end
end
