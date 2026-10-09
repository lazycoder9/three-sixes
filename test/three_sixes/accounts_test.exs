defmodule ThreeSixes.AccountsTest do
  use ThreeSixes.DataCase, async: false

  alias ThreeSixes.Accounts
  alias ThreeSixes.Accounts.Account

  defp google(uid, info) do
    %Ueberauth.Auth{
      uid: uid,
      provider: :google,
      info:
        struct(
          Ueberauth.Auth.Info,
          Map.merge(
            %{
              name: "Dana Scully",
              first_name: "Dana",
              email: "dana@example.com",
              image: "https://example.com/dana.png"
            },
            info
          )
        )
    }
  end

  describe "an Account from a Google sign-in" do
    test "is created with Google's details, and its first Nickname is the first name" do
      assert {:ok, %Account{} = account} =
               Accounts.find_or_create_from_google(google("1001", %{}))

      assert account.google_id == "1001"
      assert account.name == "Dana Scully"
      assert account.email == "dana@example.com"
      assert account.avatar_url == "https://example.com/dana.png"
      assert account.nickname == "Dana"
      assert Accounts.get_account(account.id) == account
    end

    test "takes the first word of the name for the Nickname when Google gives no first name" do
      {:ok, account} =
        Accounts.find_or_create_from_google(google(1002, %{first_name: nil, name: "Fox Mulder"}))

      assert account.google_id == "1002"
      assert account.nickname == "Fox"
    end

    test "cuts the first Nickname to 16 characters and trims it" do
      {:ok, account} =
        Accounts.find_or_create_from_google(
          google("1003", %{first_name: "  Bartholomew-Alexander  "})
        )

      assert account.nickname == "Bartholomew-Alex"
    end

    test "has no Nickname when Google gives no name at all" do
      {:ok, account} =
        Accounts.find_or_create_from_google(google("1004", %{first_name: nil, name: nil}))

      assert account.nickname == nil
    end

    test "is found again by the same Google id, with name, email and avatar refreshed and the Nickname kept" do
      {:ok, first} = Accounts.find_or_create_from_google(google("1005", %{}))
      {:ok, _renamed} = Accounts.save_nickname(first, "Agent D")

      {:ok, again} =
        Accounts.find_or_create_from_google(
          google("1005", %{
            name: "Dana Katherine Scully",
            first_name: "Katherine",
            email: "dks@example.com",
            image: "https://example.com/dks.png"
          })
        )

      assert again.id == first.id
      assert again.name == "Dana Katherine Scully"
      assert again.email == "dks@example.com"
      assert again.avatar_url == "https://example.com/dks.png"
      assert again.nickname == "Agent D"
    end

    test "may share its email with another Account" do
      {:ok, one} = Accounts.find_or_create_from_google(google("1006", %{}))
      {:ok, other} = Accounts.find_or_create_from_google(google("1007", %{}))

      assert one.id != other.id
      assert one.email == other.email
    end
  end

  describe "a dev Account" do
    test "is made from a name, and the same name finds it again" do
      {:ok, account} = Accounts.find_or_create_dev("Dana Scully")

      assert account.google_id == "dev:dana scully"
      assert account.email == "danascully@dev.localhost"
      assert account.name == "Dana Scully"
      assert account.nickname == "Dana Scully"

      assert {:ok, %Account{id: id}} = Accounts.find_or_create_dev("dana scully")
      assert id == account.id
    end
  end

  describe "saving a Nickname" do
    setup do
      {:ok, account} = Accounts.find_or_create_dev("Dana")
      %{account: account}
    end

    test "keeps it trimmed", %{account: account} do
      assert {:ok, saved} = Accounts.save_nickname(account, "  Queen of Dice ")
      assert saved.nickname == "Queen of Dice"
      assert Accounts.get_account(account.id).nickname == "Queen of Dice"
    end

    test "takes 1 to 16 characters, like a Room", %{account: account} do
      assert {:ok, %Account{nickname: "Sixteen chars ok"}} =
               Accounts.save_nickname(account, "Sixteen chars ok")

      assert {:error, _} = Accounts.save_nickname(account, "Seventeen chars!!")
      assert {:error, _} = Accounts.save_nickname(account, "   ")
      assert Accounts.get_account(account.id).nickname == "Sixteen chars ok"
    end
  end

  test "an unknown Account id finds nothing" do
    assert Accounts.get_account(-1) == nil
  end
end
