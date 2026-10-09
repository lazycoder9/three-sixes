defmodule ThreeSixes.Accounts do
  alias ThreeSixes.Accounts.Account
  alias ThreeSixes.Repo
  alias ThreeSixes.Room

  @spec get_account(term()) :: Account.t() | nil
  def get_account(id), do: Repo.get(Account, id)

  @spec find_or_create_from_google(Ueberauth.Auth.t()) ::
          {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def find_or_create_from_google(%{uid: uid, info: info}) do
    find_or_create(
      %{
        google_id: to_string(uid),
        name: info.name,
        email: info.email,
        avatar_url: info.image
      },
      info.first_name || first_word(info.name)
    )
  end

  @spec find_or_create_dev(String.t()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def find_or_create_dev(name) do
    find_or_create(
      %{
        google_id: "dev:" <> String.downcase(name),
        name: name,
        email: (name |> String.downcase() |> String.replace(~r/\s/u, "")) <> "@dev.localhost"
      },
      name
    )
  end

  @spec save_nickname(Account.t(), String.t()) ::
          {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def save_nickname(account, nickname) do
    account
    |> Account.nickname_changeset(nickname)
    |> Repo.update()
  end

  defp find_or_create(attrs, first_name) do
    case Repo.get_by(Account, google_id: attrs.google_id) do
      nil ->
        %Account{nickname: first_nickname(first_name)}
        |> Account.google_changeset(attrs)
        |> Repo.insert()

      account ->
        account
        |> Account.google_changeset(attrs)
        |> Repo.update()
    end
  end

  defp first_word(nil), do: nil
  defp first_word(name), do: name |> String.split() |> List.first()

  defp first_nickname(nil), do: nil

  defp first_nickname(name) do
    case name |> String.trim() |> String.slice(0, Room.max_nickname_length()) |> String.trim() do
      "" -> nil
      nickname -> nickname
    end
  end
end
