defmodule ThreeSixes.Accounts.Account do
  use Ecto.Schema

  import Ecto.Changeset

  alias ThreeSixes.Room

  @type t :: %__MODULE__{}

  schema "accounts" do
    field :google_id, :string
    field :name, :string
    field :email, :string
    field :avatar_url, :string
    field :nickname, :string

    timestamps(type: :utc_datetime)
  end

  @spec google_changeset(t(), map()) :: Ecto.Changeset.t()
  def google_changeset(account, attrs) do
    account
    |> cast(attrs, [:google_id, :name, :email, :avatar_url])
    |> validate_required([:google_id, :email])
    |> unique_constraint(:google_id)
  end

  @spec nickname_changeset(t(), String.t() | nil) :: Ecto.Changeset.t()
  def nickname_changeset(account, nickname) do
    account
    |> cast(%{nickname: nickname}, [:nickname], empty_values: [])
    |> update_change(:nickname, &String.trim/1)
    |> validate_required([:nickname])
    |> validate_length(:nickname, min: 1, max: Room.max_nickname_length())
  end
end
