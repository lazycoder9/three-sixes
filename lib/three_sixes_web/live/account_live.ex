defmodule ThreeSixesWeb.AccountLive do
  use ThreeSixesWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.account do
      {:ok, assign(socket, page_title: Layouts.account_name(socket.assigns.account))}
    else
      {:ok, push_navigate(socket, to: ~p"/signin?#{[return_to: ~p"/account"]}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} account={@account} return_to={~p"/account"}>
      <section class="screen account">
        <h1 class="headline">{Layouts.account_name(@account)}</h1>
        <p class="lede">Signed in with Google as {@account.email}</p>
        <p class="account__foot">
          <.link href={~p"/auth/logout"} method="delete" class="block block--birch">Log out</.link>
        </p>
      </section>
    </Layouts.app>
    """
  end
end
