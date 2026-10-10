defmodule ThreeSixes.Room do
  alias ThreeSixes.Game

  @enforce_keys [:code, :host_id]
  @max_nickname_length 16
  @capacity 30

  defstruct [:code, :host_id, members: [], game: nil, tally: %{}, last: nil]

  @type person_id :: String.t()
  @type member :: %{
          id: person_id(),
          nickname: String.t(),
          sitting_out?: boolean(),
          left?: boolean()
        }
  @type person_ref :: %{nickname: String.t(), me?: boolean(), n: pos_integer()}
  @type bid_view :: %{count: pos_integer(), face: Game.face(), by: person_ref()}
  @type game_view :: %{
          round: pos_integer(),
          dice_on_table: pos_integer(),
          seated?: boolean(),
          knocked_out?: boolean(),
          my_dice: [Game.face()] | nil,
          my_turn?: boolean(),
          can_check?: boolean(),
          turn: person_ref() | nil,
          bid: bid_view() | nil,
          seats: [
            %{
              person: person_ref(),
              dice: pos_integer(),
              said: Game.bid() | nil,
              on_turn?: boolean(),
              faces: [Game.face()] | nil,
              penalty?: boolean(),
              out?: boolean()
            }
          ],
          reveal:
            %{
              step: 0..3,
              checker: person_ref(),
              bid: bid_view(),
              count: non_neg_integer() | nil,
              stood?: boolean() | nil,
              loser: person_ref() | nil,
              knocked_out?: boolean()
            }
            | nil,
          voided_by: person_ref() | nil
        }
  @type view :: %{
          code: String.t(),
          people: [
            %{
              nickname: String.t(),
              host?: boolean(),
              me?: boolean(),
              n: pos_integer(),
              tally: non_neg_integer(),
              sitting_out?: boolean(),
              playing?: boolean()
            }
          ],
          me: String.t() | nil,
          sitting_out?: boolean(),
          playing?: boolean(),
          host?: boolean(),
          host_nickname: String.t() | nil,
          can_start?: boolean(),
          dealt_in: non_neg_integer(),
          game: game_view() | nil,
          spectators: [%{person: person_ref(), out?: boolean()}],
          over: %{winner: person_ref(), placement: [person_ref()], rounds: pos_integer()} | nil
        }
  @type t :: %__MODULE__{
          code: String.t(),
          host_id: person_id() | nil,
          members: [member()],
          game: Game.t() | nil,
          tally: %{person_id() => pos_integer()},
          last: %{placement: [person_id()], rounds: pos_integer()} | nil
        }

  @spec new(String.t(), person_id()) :: t()
  def new(code, host_id), do: %__MODULE__{code: code, host_id: host_id}

  @spec max_nickname_length() :: pos_integer()
  def max_nickname_length, do: @max_nickname_length

  @spec enter(t(), person_id(), String.t()) ::
          {:ok, t()}
          | {:taken, held :: String.t(), suggestion :: String.t()}
          | {:error, :blank | :too_long | :full}
  def enter(room, person_id, nickname) do
    cond do
      member?(room, person_id) -> {:ok, room}
      length(present(room)) >= @capacity -> {:error, :full}
      true -> add(room, person_id, nickname)
    end
  end

  defp add(room, person_id, nickname) do
    with {:ok, nickname} <- clean(nickname) do
      case holder(room, nickname) do
        nil -> {:ok, room |> put_member(member(person_id, nickname)) |> claim_host(person_id)}
        holder -> {:taken, holder.nickname, suggestion(room, holder.nickname)}
      end
    end
  end

  defp put_member(room, %{id: id} = member) do
    if Enum.any?(room.members, &(&1.id == id)),
      do: update_member(room, id, fn _left -> member end),
      else: %{room | members: room.members ++ [member]}
  end

  defp update_member(room, id, fun) do
    members =
      Enum.map(room.members, fn
        %{id: ^id} = member -> fun.(member)
        member -> member
      end)

    %{room | members: members}
  end

  defp claim_host(%{host_id: nil} = room, person_id), do: %{room | host_id: person_id}
  defp claim_host(room, _person_id), do: room

  defp member(person_id, nickname),
    do: %{id: person_id, nickname: nickname, sitting_out?: false, left?: false}

  defp present(room), do: Enum.reject(room.members, & &1.left?)

  defp clean(nickname) when not is_binary(nickname), do: {:error, :blank}

  defp clean(nickname) do
    nickname = String.trim(nickname)

    cond do
      nickname == "" -> {:error, :blank}
      String.length(nickname) > @max_nickname_length -> {:error, :too_long}
      true -> {:ok, nickname}
    end
  end

  defp holder(room, nickname) do
    wanted = String.downcase(nickname)
    Enum.find(present(room), &(String.downcase(&1.nickname) == wanted))
  end

  defp suggestion(room, held) do
    base = String.replace(held, ~r/ \d+$/u, "")

    2
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(&numbered(base, &1))
    |> Enum.find(&(holder(room, &1) == nil))
  end

  defp numbered(base, number) do
    suffix = " #{number}"

    base =
      base
      |> String.slice(0, @max_nickname_length - String.length(suffix))
      |> String.trim_trailing()

    base <> suffix
  end

  @spec member?(t(), person_id()) :: boolean()
  def member?(room, person_id), do: Enum.any?(present(room), &(&1.id == person_id))

  @spec sit_out(t(), person_id(), boolean()) :: {:ok, t()} | {:error, :not_member}
  def sit_out(room, person_id, sitting_out?) when is_boolean(sitting_out?) do
    if member?(room, person_id) do
      {:ok, update_member(room, person_id, &%{&1 | sitting_out?: sitting_out?})}
    else
      {:error, :not_member}
    end
  end

  @spec leave(t(), person_id(), [person_id()]) :: {:ok | :roll, t()} | {:error, :not_member}
  def leave(room, id, connected) do
    if member?(room, id) do
      room
      |> update_member(id, &%{&1 | left?: true})
      |> pass_host(id, connected)
      |> leave_game(id)
    else
      {:error, :not_member}
    end
  end

  @spec remove(t(), person_id(), pos_integer(), [person_id()]) ::
          {:ok | :roll, t()} | {:error, :not_host | :not_member | :self}
  def remove(room, by, n, connected) do
    with {:ok, id} <- other_present(room, by, n), do: leave(room, id, connected)
  end

  @spec make_host(t(), person_id(), pos_integer()) ::
          {:ok, t()} | {:error, :not_host | :not_member | :self}
  def make_host(room, by, n) do
    with {:ok, id} <- other_present(room, by, n), do: {:ok, %{room | host_id: id}}
  end

  defp other_present(%{host_id: host_id} = room, host_id, n) do
    case Enum.find(Enum.with_index(room.members, 1), &match?({%{left?: false}, ^n}, &1)) do
      nil -> {:error, :not_member}
      {%{id: ^host_id}, _n} -> {:error, :self}
      {%{id: id}, _n} -> {:ok, id}
    end
  end

  defp other_present(_room, _by, _n), do: {:error, :not_host}

  defp pass_host(%{host_id: id} = room, id, connected),
    do: %{room | host_id: Enum.find(connected, &member?(room, &1)) || first_present(room)}

  defp pass_host(room, _id, _connected), do: room

  defp first_present(room) do
    case present(room) do
      [first | _] -> first.id
      [] -> nil
    end
  end

  defp leave_game(%{game: nil} = room, _id), do: {:ok, room}

  defp leave_game(room, id) do
    case Game.leave(room.game, id) do
      {:void, game} -> {:roll, %{room | game: game}}
      {:ok, game} -> {:ok, %{room | game: game}}
      {:over, game} -> {:ok, game_over(%{room | game: game})}
    end
  end

  @spec dealt_in(t()) :: [person_id()]
  def dealt_in(room), do: for(member <- present(room), not member.sitting_out?, do: member.id)

  @spec start_game(t(), person_id(), [person_id()]) ::
          {:ok, t()} | {:error, :not_host | :playing | :too_few | :wrong_seats}
  def start_game(room, by, seats) do
    dealt_in = dealt_in(room)

    cond do
      by != room.host_id -> {:error, :not_host}
      room.game != nil -> {:error, :playing}
      length(dealt_in) < 2 -> {:error, :too_few}
      Enum.sort(seats) != Enum.sort(dealt_in) -> {:error, :wrong_seats}
      true -> {:ok, %{room | game: Game.new(seats), last: nil}}
    end
  end

  @spec start_round(t(), %{person_id() => [Game.face()]}) :: t()
  def start_round(room, dice), do: %{room | game: Game.start_round(room.game, dice)}

  @spec raise(t(), person_id(), term(), term()) ::
          {:ok, t()} | {:error, :not_bidding | :not_your_turn | :illegal}
  def raise(%{game: nil}, _by, _count, _face), do: {:error, :not_bidding}

  def raise(room, by, count, face) do
    with {:ok, game} <- Game.raise(room.game, by, count, face), do: {:ok, %{room | game: game}}
  end

  @spec check(t(), person_id()) ::
          {:ok, t()} | {:error, :not_bidding | :not_your_turn | :no_bid}
  def check(%{game: nil}, _by), do: {:error, :not_bidding}

  def check(room, by) do
    with {:ok, game} <- Game.check(room.game, by), do: {:ok, %{room | game: game}}
  end

  @spec reveal(t(), pos_integer(), 1..3) :: {:ok, t()} | :stale
  def reveal(%{game: %Game{round: round, reveal: %{}} = game} = room, round, step),
    do: {:ok, %{room | game: Game.advance_reveal(game, step)}}

  def reveal(_room, _round, _step), do: :stale

  @spec next_round(t(), pos_integer()) :: :stale | {:roll, t()} | {:over, t()}
  def next_round(room, round) do
    case reveal(room, round, 3) do
      {:ok, room} -> if Game.over?(room.game), do: {:over, game_over(room)}, else: {:roll, room}
      :stale -> :stale
    end
  end

  defp game_over(%{game: game} = room) do
    [winner | _] = placement = Game.placement(game)

    %{
      room
      | game: nil,
        tally: Map.update(room.tally, winner, 1, &(&1 + 1)),
        last: %{placement: placement, rounds: game.round}
    }
  end

  @spec reveal_schedule(t()) :: [
          {pos_integer(), {:reveal, pos_integer(), 1..3} | {:next_round, pos_integer()}}
        ]
  def reveal_schedule(%{game: %Game{round: round}}) do
    [
      {1100, {:reveal, round, 1}},
      {2700, {:reveal, round, 2}},
      {4300, {:reveal, round, 3}},
      {8200, {:next_round, round}}
    ]
  end

  @spec view_for(t(), person_id()) :: view()
  def view_for(room, person_id) do
    me = find_member(room, person_id)
    host = find_member(room, room.host_id)
    host? = person_id == room.host_id
    dealt_in = length(dealt_in(room))

    %{
      code: room.code,
      people:
        for {member, n} <- Enum.with_index(room.members, 1), not member.left? do
          %{
            nickname: member.nickname,
            host?: member.id == room.host_id,
            me?: member.id == person_id,
            n: n,
            tally: Map.get(room.tally, member.id, 0),
            sitting_out?: member.sitting_out?,
            playing?: playing?(room, member.id)
          }
        end,
      me: me && me.nickname,
      sitting_out?: me != nil and me.sitting_out?,
      playing?: playing?(room, person_id),
      host?: host?,
      host_nickname: host && host.nickname,
      can_start?: host? and room.game == nil and dealt_in >= 2,
      dealt_in: dealt_in,
      game: room.game && game_view(room, room.game, person_id),
      spectators: spectators(room, person_id),
      over: over_view(room, person_id)
    }
  end

  defp playing?(%{game: nil}, _id), do: false
  defp playing?(%{game: game}, id), do: id in game.seats and id not in game.out

  defp spectators(%{game: nil}, _viewer), do: []

  defp spectators(%{game: game} = room, viewer) do
    for %{id: id} <- present(room), id not in game.seats or id in game.out do
      %{person: person_ref(room, id, viewer), out?: id in game.out}
    end
  end

  defp over_view(%{game: nil, last: %{placement: [winner | _] = placement} = last} = room, viewer) do
    ref = &person_ref(room, &1, viewer)
    %{winner: ref.(winner), placement: Enum.map(placement, ref), rounds: last.rounds}
  end

  defp over_view(_room, _viewer), do: nil

  defp game_view(room, game, viewer) do
    ref = &person_ref(room, &1, viewer)
    knocked_out? = out?(game, viewer)
    seated? = viewer in game.seats and not knocked_out?
    my_turn? = seated? and game.turn == viewer

    %{
      round: game.round,
      dice_on_table: Game.dice_on_table(game),
      seated?: seated?,
      knocked_out?: knocked_out?,
      my_dice: game.dice[viewer],
      my_turn?: my_turn?,
      can_check?: my_turn? and game.bid != nil and game.reveal == nil,
      turn: game.turn && ref.(game.turn),
      bid: game.bid && bid_view(game.bid, ref),
      seats: game.seats |> from_seat(viewer) |> Enum.map(&seat_view(game, &1, ref)),
      reveal: game.reveal && reveal_view(game, ref),
      voided_by: game.voided_by && ref.(game.voided_by)
    }
  end

  defp from_seat(seats, viewer) do
    case Enum.find_index(seats, &(&1 == viewer)) do
      nil -> seats
      index -> Enum.drop(seats, index) ++ Enum.take(seats, index)
    end
  end

  defp seat_view(game, seat, ref) do
    reveal = game.reveal || %{step: 0, loser: nil}

    %{
      person: ref.(seat),
      dice: game.counts[seat],
      said: game.said[seat],
      on_turn?: game.turn == seat,
      faces: if(reveal.step >= 1, do: game.dice[seat]),
      penalty?: reveal.step >= 3 and reveal.loser == seat,
      out?: out?(game, seat)
    }
  end

  defp out?(%{reveal: %{loser: seat}}, seat), do: false
  defp out?(game, seat), do: seat in game.out

  defp reveal_view(%{reveal: reveal} = game, ref) do
    counted? = reveal.step >= 2
    penalized? = reveal.step >= 3

    %{
      step: reveal.step,
      checker: ref.(reveal.checker),
      bid: bid_view(reveal.bid, ref),
      count: if(counted?, do: reveal.count),
      stood?: if(counted?, do: reveal.stood?),
      loser: if(penalized?, do: ref.(reveal.loser)),
      knocked_out?: penalized? and reveal.loser in game.out
    }
  end

  defp bid_view(bid, ref), do: %{count: bid.count, face: bid.face, by: ref.(bid.by)}

  defp person_ref(room, person_id, viewer) do
    {member, n} =
      room.members
      |> Enum.with_index(1)
      |> Enum.find(fn {member, _n} -> member.id == person_id end)

    %{nickname: member.nickname, me?: person_id == viewer, n: n}
  end

  defp find_member(room, person_id), do: Enum.find(present(room), &(&1.id == person_id))
end
