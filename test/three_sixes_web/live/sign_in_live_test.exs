defmodule ThreeSixesWeb.SignInLiveTest do
  use ThreeSixesWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "the sign-in page offers Google, the chat-app hint and the dev login", %{conn: conn} do
    {:ok, view, _html} = conn |> guest("dana") |> live(~p"/signin?return_to=/r/KQXT")

    assert has_element?(view, ".sticky h1", "Keep your record.")

    assert has_element?(
             view,
             ~s(a[href="/auth/google?return_to=%2Fr%2FKQXT"]),
             "Sign in with Google"
           )

    assert has_element?(
             view,
             ".hint",
             "Doesn't work inside some chat apps? Open in Safari or Chrome."
           )

    assert has_element?(view, ~s(form.dev[action="/auth/dev"][method="post"]))
    assert has_element?(view, ~s(.dev input[name="name"][value="Dana"]))
    assert has_element?(view, ~s(.dev input[type="hidden"][name="return_to"][value="/r/KQXT"]))
    assert has_element?(view, ".dev button", "Dev login")
  end

  test "without Google set up the sign-in page offers only the dev login", %{conn: conn} do
    google = Application.fetch_env!(:ueberauth, Ueberauth.Strategy.Google.OAuth)
    Application.put_env(:ueberauth, Ueberauth.Strategy.Google.OAuth, [])

    on_exit(fn -> Application.put_env(:ueberauth, Ueberauth.Strategy.Google.OAuth, google) end)

    {:ok, view, _html} = conn |> guest("dana") |> live(~p"/signin?return_to=/account")

    assert has_element?(view, ".sticky h1", "Keep your record.")
    refute has_element?(view, ~s(a[href^="/auth/google"]))
    refute has_element?(view, ".hint", "Open in Safari or Chrome.")
    assert has_element?(view, ".dev button", "Dev login")
  end

  test "signing in through the dev login comes back to the page with the Account in the header",
       %{conn: conn} do
    conn = conn |> guest("dana") |> post(~p"/auth/dev", %{name: "Dana", return_to: "/"})
    assert redirected_to(conn) == "/"

    {:ok, view, _html} = conn |> recycle() |> live(~p"/")

    assert has_element?(view, ~s(header.top nav a[href="/account"] .token), "D")
    assert has_element?(view, ~s(header.top nav a[href="/account"]), "Dana")
    refute has_element?(view, "header.top nav a", "Sign in")
  end

  test "the account page shows the Nickname and the Google email, and Log out makes the device a Guest again",
       %{conn: conn} do
    conn = conn |> guest("dana") |> sign_in("Dana Scully")

    {:ok, view, _html} = live(conn, ~p"/account")

    assert has_element?(view, "h1", "Dana Scully")
    assert has_element?(view, "p", "Signed in with Google as danascully@dev.localhost")

    logout = element(view, ~s(a[href="/auth/logout"][data-method="delete"]), "Log out")
    assert has_element?(logout)

    conn = conn |> recycle() |> delete(~p"/auth/logout")
    assert redirected_to(conn) == "/"

    {:ok, landing, _html} = conn |> recycle() |> live(~p"/")

    assert has_element?(landing, ~s(header.top nav a[href="/signin?return_to=%2F"]), "Sign in")
    refute has_element?(landing, ~s(header.top nav a[href="/account"]))

    assert {:error, {:live_redirect, %{to: "/signin?return_to=%2Faccount"}}} =
             conn |> recycle() |> live(~p"/account")
  end

  test "someone already signed in who opens the sign-in page goes to the account page",
       %{conn: conn} do
    conn = conn |> guest("dana") |> sign_in("Dana")

    assert {:error, {:live_redirect, %{to: "/account"}}} = live(conn, ~p"/signin")
  end

  test "Log out is only on the account page", %{conn: conn} do
    conn = conn |> guest("dana") |> sign_in("Dana")

    {:ok, landing, _html} = live(conn, ~p"/")

    refute has_element?(landing, ~s(a[href="/auth/logout"]))
  end

  defp sign_in(conn, name) do
    conn |> post(~p"/auth/dev", %{name: name}) |> recycle()
  end

  defp guest(conn, guest_id), do: init_test_session(conn, %{"guest_id" => guest_id})
end
