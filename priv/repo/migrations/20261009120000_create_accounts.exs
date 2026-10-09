defmodule ThreeSixes.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts) do
      add :google_id, :string, null: false
      add :name, :string
      add :email, :string, null: false
      add :avatar_url, :string
      add :nickname, :string

      timestamps(type: :utc_datetime)
    end

    # SQLite has no concurrent index builds, and the table is new and empty here.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:accounts, [:google_id])
  end
end
