defmodule ThreeSixes.Repo.Migrations.CreateGameRecords do
  use Ecto.Migration

  # The tables are new and empty, so their foreign keys and indexes lock nothing.
  def change do
    create table(:game_records) do
      add :room_code, :string, null: false
      add :rounds, :integer, null: false
      add :finished_at, :utc_datetime_usec, null: false
    end

    create table(:placements) do
      # excellent_migrations:safety-assured-for-next-line column_reference_added
      add :game_record_id, references(:game_records, on_delete: :delete_all), null: false
      add :person_id, :string, null: false
      add :nickname, :string, null: false
      add :place, :integer, null: false
    end

    create table(:check_records) do
      # excellent_migrations:safety-assured-for-next-line column_reference_added
      add :game_record_id, references(:game_records, on_delete: :delete_all), null: false
      add :round, :integer, null: false
      add :checker_id, :string, null: false
      add :bidder_id, :string, null: false
      add :stood, :boolean, null: false
    end

    create table(:guest_merges, primary_key: false) do
      add :guest_id, :string, primary_key: true
      # excellent_migrations:safety-assured-for-next-line column_reference_added
      add :account_id, references(:accounts), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    # SQLite has no concurrent index builds.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:placements, [:game_record_id, :person_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:placements, [:person_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:check_records, [:game_record_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:check_records, [:checker_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:check_records, [:bidder_id])
  end
end
