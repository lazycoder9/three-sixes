defmodule ThreeSixesWeb.SignInLive do
  use ThreeSixesWeb, :live_view

  alias ThreeSixesWeb.AuthController

  @impl true
  def mount(params, _session, socket) do
    if socket.assigns.account do
      {:ok, push_navigate(socket, to: ~p"/account")}
    else
      {:ok,
       assign(socket,
         page_title: "Sign in",
         return_to: params["return_to"] || ~p"/",
         dev_login?: AuthController.dev_login_enabled?()
       )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} account={@account} return_to={nil}>
      <section class="screen screen--narrow">
        <.sticky_note>
          <h1>Keep your record.</h1>
          <p>
            Sign in and your Nickname, stats and Game history follow you to any device. You never have to. Guests can play everything.
          </p>
          <div class="gap"></div>
          <a
            href={~p"/auth/google?#{[return_to: @return_to]}"}
            class="block block--white block--big block--wide"
          >
            <.google_g /> Sign in with Google
          </a>
          <p class="hint">Doesn't work inside some chat apps? Open in Safari or Chrome.</p>
          <.form
            :if={@dev_login?}
            for={%{"name" => "Dana", "return_to" => @return_to}}
            action={~p"/auth/dev"}
            method="post"
            class="dev"
          >
            <p>
              <span class="hl">Development only.</span> Skip Google and sign in as a test Account.
            </p>
            <.write_on_line id="dev-name" name="name" label="Name" value="Dana" maxlength="16" />
            <input type="hidden" name="return_to" value={@return_to} />
            <.block type="submit">Dev login</.block>
          </.form>
        </.sticky_note>
      </section>
    </Layouts.app>
    """
  end

  defp google_g(assigns) do
    ~H"""
    <svg viewBox="0 0 48 48" width="18" height="18" aria-hidden="true">
      <path
        fill="#EA4335"
        d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"
      />
      <path
        fill="#4285F4"
        d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"
      />
      <path
        fill="#FBBC05"
        d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"
      />
      <path
        fill="#34A853"
        d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"
      />
    </svg>
    """
  end
end
