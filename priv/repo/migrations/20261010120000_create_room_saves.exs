defmodule ThreeSixes.Repo.Migrations.CreateRoomSaves do
  use Ecto.Migration

  def change do
    create table(:room_saves, primary_key: false) do
      add :code, :string, primary_key: true
      add :room, :binary, null: false
      add :closes_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end
  end
end
