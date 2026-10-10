defmodule ThreeSixes.Accounts.GuestMerge do
  use Ecto.Schema

  alias ThreeSixes.Accounts.Account

  @type t :: %__MODULE__{}

  @primary_key {:guest_id, :string, autogenerate: false}
  schema "guest_merges" do
    belongs_to :account, Account

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
