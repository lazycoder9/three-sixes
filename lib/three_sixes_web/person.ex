defmodule ThreeSixesWeb.Person do
  alias ThreeSixes.Accounts

  @spec on_mount(:default, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, session, socket) do
    {person_id, account} = person(session)

    {:cont,
     Phoenix.Component.assign(socket,
       person_id: person_id,
       account: account,
       client_address: client_address(socket)
     )}
  end

  defp person(%{"account_id" => account_id} = session) do
    case Accounts.get_account(account_id) do
      nil -> guest(session)
      account -> {"account:" <> to_string(account.id), account}
    end
  end

  defp person(session), do: guest(session)

  defp guest(%{"guest_id" => guest_id}), do: {"guest:" <> guest_id, nil}

  defp client_address(socket) do
    forwarded =
      for {"x-forwarded-for", value} <-
            Phoenix.LiveView.get_connect_info(socket, :x_headers) || [],
          do: value

    case forwarded |> List.last("") |> String.split(",") |> List.last() |> String.trim() do
      "" -> peer_address(Phoenix.LiveView.get_connect_info(socket, :peer_data))
      address -> address
    end
  end

  defp peer_address(%{address: address}), do: address |> :inet.ntoa() |> to_string()
  defp peer_address(nil), do: nil
end
