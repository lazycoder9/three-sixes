defmodule ThreeSixes.Rooms.Save do
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:code, :string, autogenerate: false}

  schema "room_saves" do
    field :room, :binary
    field :closes_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end
