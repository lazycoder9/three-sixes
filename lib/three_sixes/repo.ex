defmodule ThreeSixes.Repo do
  use Ecto.Repo,
    otp_app: :three_sixes,
    adapter: Ecto.Adapters.SQLite3
end
