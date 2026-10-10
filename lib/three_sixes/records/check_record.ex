defmodule ThreeSixes.Records.CheckRecord do
  use Ecto.Schema

  import Ecto.Changeset

  alias ThreeSixes.Records.GameRecord

  @type t :: %__MODULE__{}

  schema "check_records" do
    belongs_to :game_record, GameRecord
    field :round, :integer
    field :checker_id, :string
    field :bidder_id, :string
    field :stood, :boolean
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(check, attrs) do
    check
    |> cast(attrs, [:round, :checker_id, :bidder_id, :stood])
    |> validate_required([:round, :checker_id, :bidder_id, :stood])
  end
end
