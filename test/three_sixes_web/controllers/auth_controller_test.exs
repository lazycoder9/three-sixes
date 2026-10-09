defmodule ThreeSixesWeb.AuthControllerTest do
  use ThreeSixesWeb.ConnCase, async: false

  alias ThreeSixes.Accounts
  alias ThreeSixesWeb.AuthController

  @auth %Ueberauth.Auth{
    uid: "109876543210",
    provider: :google,
    info: %Ueberauth.Auth.Info{
      name: "Dana Scully",
      first_name: "Dana",
      email: "dana@example.com",
      image: "https://example.com/dana.png"
    }
  }

  defp google_callback(session, assigns) do
    conn =
      build_conn()
      |> init_test_session(session)
      |> fetch_flash()

    assigns
    |> Enum.reduce(conn, fn {key, value}, conn -> assign(conn, key, value) end)
    |> AuthController.callback(%{})
  end

  describe "the Google callback" do
    test "signs the Account in, keeps the Guest id, renews the session and goes back where the person came from" do
      conn =
        google_callback(%{"guest_id" => "g1", "return_to" => "/r/KQXT"}, ueberauth_auth: @auth)

      assert redirected_to(conn) == "/r/KQXT"
      account = Accounts.get_account(get_session(conn, "account_id"))
      assert account.google_id == "109876543210"
      assert account.nickname == "Dana"
      assert get_session(conn, "guest_id") == "g1"
      assert get_session(conn, "return_to") == nil
      assert conn.private[:plug_session_info] == :renew
    end

    test "goes to the landing page when no path was stored" do
      conn = google_callback(%{"guest_id" => "g1"}, ueberauth_auth: @auth)

      assert redirected_to(conn) == "/"
      assert get_session(conn, "account_id")
    end

    for path <- ["//evil.com", "https://evil.com", "/\\evil.com", "/%09/evil.com", "/\t/evil.com"] do
      test "goes to the landing page instead of #{inspect(path)}" do
        conn =
          google_callback(%{"guest_id" => "g1", "return_to" => unquote(path)},
            ueberauth_auth: @auth
          )

        assert redirected_to(conn) == "/"
      end
    end

    test "a failed sign-in goes back to the sign-in page with the reason, still a Guest" do
      failure = %Ueberauth.Failure{
        provider: :google,
        errors: [
          %Ueberauth.Failure.Error{
            message_key: "csrf_attack",
            message: "Cross-Site Request Forgery attack"
          }
        ]
      }

      conn = google_callback(%{"guest_id" => "g1"}, ueberauth_failure: failure)

      assert redirected_to(conn) == "/signin"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Cross-Site Request Forgery attack"
      assert get_session(conn, "account_id") == nil
    end
  end

  describe "the Google request" do
    test "remembers a local return path and sends the person to Google for their email and profile",
         %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-forwarded-proto", "https")
        |> get(~p"/auth/google?return_to=/r/KQXT")

      assert get_session(conn, "return_to") == "/r/KQXT"

      location = URI.parse(redirected_to(conn))
      assert location.host == "accounts.google.com"
      query = URI.decode_query(location.query)
      assert query["scope"] == "email profile"
      assert query["redirect_uri"] == "https://www.example.com/auth/google/callback"
    end

    test "does not remember a path that leaves the site", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{"return_to" => "/r/OLDX"})
        |> get(~p"/auth/google?return_to=//evil.com")

      assert get_session(conn, "return_to") == nil
      assert URI.parse(redirected_to(conn)).host == "accounts.google.com"
    end
  end

  describe "the dev login" do
    setup do
      on_exit(fn -> Application.put_env(:three_sixes, :dev_login_enabled, true) end)
    end

    test "signs in as a test Account by name and goes back where the person came from",
         %{conn: conn} do
      conn = post(conn, ~p"/auth/dev", %{"name" => " Fox ", "return_to" => "/r/KQXT"})

      assert redirected_to(conn) == "/r/KQXT"
      account = Accounts.get_account(get_session(conn, "account_id"))
      assert account.name == "Fox"
      assert account.nickname == "Fox"
      assert account.email == "fox@dev.localhost"
      assert get_session(conn, "guest_id")
    end

    test "the same name signs in as the same Account, another name as another", %{conn: conn} do
      fox = conn |> post(~p"/auth/dev", %{"name" => "Fox"}) |> get_session("account_id")
      again = build_conn() |> post(~p"/auth/dev", %{"name" => "fox"}) |> get_session("account_id")
      dana = build_conn() |> post(~p"/auth/dev", %{"name" => "Dana"}) |> get_session("account_id")

      assert fox == again
      assert fox != dana
    end

    test "a blank name signs in as Dana, and a path that leaves the site goes to the landing page",
         %{conn: conn} do
      conn = post(conn, ~p"/auth/dev", %{"name" => "  ", "return_to" => "//evil.com"})

      assert redirected_to(conn) == "/"
      assert Accounts.get_account(get_session(conn, "account_id")).name == "Dana"
    end

    test "is refused when the dev login is off", %{conn: conn} do
      Application.put_env(:three_sixes, :dev_login_enabled, false)

      conn = post(conn, ~p"/auth/dev", %{"name" => "Fox"})

      assert redirected_to(conn) == "/signin"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Dev login"
      assert get_session(conn, "account_id") == nil
    end
  end

  test "logging out forgets the Account and gives the device a fresh Guest id", %{conn: conn} do
    {:ok, account} = Accounts.find_or_create_dev("Fox")

    conn =
      conn
      |> init_test_session(%{"guest_id" => "old", "account_id" => account.id})
      |> delete(~p"/auth/logout")

    assert redirected_to(conn) == "/"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "You're logged out."
    assert get_session(conn, "account_id") == nil
    assert get_session(conn, "guest_id") not in [nil, "old"]
    assert conn.private[:plug_session_info] == :renew
  end

  describe "whether signing in is possible" do
    setup do
      google = Application.get_env(:ueberauth, Ueberauth.Strategy.Google.OAuth)

      on_exit(fn ->
        Application.put_env(:ueberauth, Ueberauth.Strategy.Google.OAuth, google)
        Application.put_env(:three_sixes, :dev_login_enabled, true)
      end)
    end

    test "it is with Google configured or the dev login on, and not with neither" do
      Application.put_env(:three_sixes, :dev_login_enabled, false)
      assert AuthController.sign_in_available?()

      Application.delete_env(:ueberauth, Ueberauth.Strategy.Google.OAuth)
      refute AuthController.sign_in_available?()

      Application.put_env(:three_sixes, :dev_login_enabled, true)
      assert AuthController.sign_in_available?()
    end
  end
end
