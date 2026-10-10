defmodule ThreeSixesWeb.AuthControllerTest do
  use ThreeSixesWeb.ConnCase, async: false

  alias ThreeSixes.Accounts
  alias ThreeSixes.Records
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
      assert get_session(conn, "was_guest_id") == "g1"
      assert get_session(conn, "new_account") == true
      assert get_session(conn, "return_to") == nil
      assert conn.private[:plug_session_info] == :renew
    end

    test "of an Account that already exists marks the session as not a new Account" do
      {:created, _account} = Accounts.find_or_create_from_google(@auth)

      conn =
        google_callback(%{"guest_id" => "g1", "new_account" => true}, ueberauth_auth: @auth)

      assert get_session(conn, "account_id")
      assert get_session(conn, "was_guest_id") == "g1"
      assert get_session(conn, "new_account") == nil
    end

    test "tells the Guest's other tabs to disconnect, and gives the Account a live socket id of its own" do
      ThreeSixesWeb.Endpoint.subscribe("guest_session:g1")

      conn =
        google_callback(%{"guest_id" => "g1", "live_socket_id" => "guest_session:g1"},
          ueberauth_auth: @auth
        )

      assert_receive %Phoenix.Socket.Broadcast{topic: "guest_session:g1", event: "disconnect"}
      assert "account_session:" <> _ = get_session(conn, "live_socket_id")
    end

    test "with no Guest id in the session still signs the Account in" do
      conn = google_callback(%{}, ueberauth_auth: @auth)

      assert redirected_to(conn) == "/"
      assert get_session(conn, "account_id")
      assert get_session(conn, "was_guest_id") == nil
    end

    test "goes to the landing page when no path was stored" do
      conn = google_callback(%{"guest_id" => "g1"}, ueberauth_auth: @auth)

      assert redirected_to(conn) == "/"
      assert get_session(conn, "account_id")
    end

    for path <- [
          "//evil.com",
          "https://evil.com",
          "/\\evil.com",
          "/%09/evil.com",
          "/\t/evil.com",
          "/foo\nbar",
          "/foo\rbar",
          "/foo\0bar",
          "/foo\x7Fbar"
        ] do
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

    test "a failed sign-in keeps the path the person came from, for the next try" do
      failure = %Ueberauth.Failure{
        provider: :google,
        errors: [%Ueberauth.Failure.Error{message_key: "access_denied", message: "denied"}]
      }

      no_email = %{@auth | info: %{@auth.info | email: nil}}

      for assigns <- [[ueberauth_failure: failure], [ueberauth_auth: no_email]] do
        conn = google_callback(%{"guest_id" => "g1", "return_to" => "/account"}, assigns)

        assert redirected_to(conn) == "/signin?return_to=%2Faccount"
        assert get_session(conn, "account_id") == nil
      end
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
      assert get_session(conn, "was_guest_id") == get_session(conn, "guest_id")
      assert get_session(conn, "new_account") == true
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

    test "takes over the device's Guest history, so its Games count for the Account",
         %{conn: conn} do
      {:ok, _record} =
        Records.record_game(%{
          room_code: "KQXT",
          rounds: 4,
          placement: [
            %{person_id: "guest:g1", nickname: "Foxy", place: 1},
            %{person_id: "guest:g2", nickname: "Dana", place: 2}
          ],
          checks: [%{round: 2, checker: "guest:g1", bidder: "guest:g2", stood?: false}]
        })

      conn =
        conn
        |> init_test_session(%{"guest_id" => "g1"})
        |> post(~p"/auth/dev", %{"name" => "Fox"})

      fox = Accounts.person_id(Accounts.get_account(get_session(conn, "account_id")))
      assert %{games: 1, wins: 1, checks_won: 1} = Accounts.stats(fox)
      assert [%{players: [%{nickname: "Foxy", me?: true}, _]}] = Accounts.recent_games(fox)
      assert %{games: 0} = Accounts.stats("guest:g1")
      assert %{games: 1} = Accounts.stats("guest:g2")
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
    {:created, account} = Accounts.find_or_create_dev("Fox")

    conn =
      conn
      |> init_test_session(%{
        "guest_id" => "old",
        "account_id" => account.id,
        "was_guest_id" => "old",
        "new_account" => true
      })
      |> delete(~p"/auth/logout")

    assert redirected_to(conn) == "/"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "You're logged out."
    assert get_session(conn, "account_id") == nil
    assert get_session(conn, "was_guest_id") == nil
    assert get_session(conn, "new_account") == nil
    assert get_session(conn, "guest_id") not in [nil, "old"]
    assert conn.private[:plug_session_info] == :renew
  end

  test "signing in again disconnects the LiveViews of the sign-in it replaces", %{conn: conn} do
    conn = post(conn, ~p"/auth/dev", %{"name" => "Fox"})
    fox = get_session(conn, "live_socket_id")
    ThreeSixesWeb.Endpoint.subscribe(fox)

    conn = conn |> recycle() |> post(~p"/auth/dev", %{"name" => "Fox"})

    assert_receive %Phoenix.Socket.Broadcast{topic: ^fox, event: "disconnect"}
    assert "account_session:" <> _ = get_session(conn, "live_socket_id")
    assert get_session(conn, "live_socket_id") != fox
    assert get_session(conn, "new_account") == nil
  end

  test "logging out disconnects the LiveViews of this sign-in only", %{conn: conn} do
    conn = post(conn, ~p"/auth/dev", %{"name" => "Fox"})
    live_socket_id = get_session(conn, "live_socket_id")
    other_device = build_conn() |> post(~p"/auth/dev", %{"name" => "Fox"})

    assert "account_session:" <> _ = live_socket_id
    assert get_session(other_device, "live_socket_id") != live_socket_id

    ThreeSixesWeb.Endpoint.subscribe(live_socket_id)
    conn = conn |> recycle() |> delete(~p"/auth/logout")

    assert_receive %Phoenix.Socket.Broadcast{topic: ^live_socket_id, event: "disconnect"}
    assert get_session(conn, "live_socket_id") == nil
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
