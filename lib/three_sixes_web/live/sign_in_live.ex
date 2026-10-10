defmodule ThreeSixesWeb.SignInLive do
  use ThreeSixesWeb, :live_view

  @impl true
  def mount(params, _session, socket) do
    if socket.assigns.account do
      {:ok, push_navigate(socket, to: ~p"/account")}
    else
      {:ok,
       assign(socket,
         page_title: "Sign in",
         return_to: params["return_to"] || ~p"/"
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
          <Layouts.sign_in_options return_to={@return_to} />
        </.sticky_note>
      </section>
    </Layouts.app>
    """
  end
end
