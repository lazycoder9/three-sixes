defmodule ThreeSixes.Room do
  alias ThreeSixes.Game

  @enforce_keys [:code, :host_id]
  @max_nickname_length 16
  @capacity 30
  @handover_after :timer.minutes(2)
  @vote_for :timer.seconds(30)
  @vote_again_after :timer.seconds(30)

  defstruct [
    :code,
    :host_id,
    members: [],
    game: nil,
    tally: %{},
    last: nil,
    away: %{},
    handover: nil
  ]

  @type person_id :: String.t()
  @type member :: %{
          id: person_id(),
          nickname: String.t(),
          sitting_out?: boolean(),
          blind?: boolean(),
          left?: boolean(),
          removed?: boolean()
        }
  @type person_ref :: %{nickname: String.t(), me?: boolean(), n: pos_integer()}
  @type bid_view :: %{
          count: pos_integer(),
          face: Game.face(),
          by: person_ref(),
          blind?: boolean()
        }
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
          three_sixes?: boolean(),
          seats: [
            %{
              person: person_ref(),
              dice: pos_integer(),
              said: Game.said() | nil,
              on_turn?: boolean(),
              faces: [Game.face()] | nil,
              penalty?: boolean(),
              out?: boolean(),
              blind?: boolean(),
              peeked?: boolean()
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
              penalty: 1..2 | nil,
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
          removed?: boolean(),
          sitting_out?: boolean(),
          blind?: boolean(),
          playing?: boolean(),
          host?: boolean(),
          host_nickname: String.t() | nil,
          can_start?: boolean(),
          dealt_in: non_neg_integer(),
          game: game_view() | nil,
          spectators: [%{person: person_ref(), out?: boolean()}],
          away: %{pos_integer() => integer()},
          host_away:
            %{
              since: integer(),
              ends_at: integer(),
              vote:
                %{
                  by: person_ref(),
                  yes: non_neg_integer(),
                  of: non_neg_integer(),
                  ends_at: integer(),
                  said_yes?: boolean()
                }
                | nil,
              vote_again_at: integer() | nil
            }
            | nil,
          over: %{winner: person_ref(), placement: [person_ref()], rounds: pos_integer()} | nil
        }
  @type handover :: %{
          host: person_id(),
          ends_at: integer(),
          vote: %{by: person_id(), yes: [person_id()], ends_at: integer()} | nil,
          vote_again_at: integer() | nil
        }
  @type t :: %__MODULE__{
          code: String.t(),
          host_id: person_id() | nil,
          members: [member()],
          game: Game.t() | nil,
          tally: %{person_id() => pos_integer()},
          last: %{placement: [person_id()], rounds: pos_integer(), checks: [Game.check()]} | nil,
          away: %{person_id() => integer()},
          handover: handover() | nil
        }
  @type finished :: %{
          room_code: String.t(),
          rounds: pos_integer(),
          placement: [%{person_id: person_id(), nickname: String.t(), place: pos_integer()}],
          checks: [Game.check()]
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
      case holder(room, nickname, person_id) do
        nil -> {:ok, room |> put_member(member(person_id, nickname)) |> claim_host(person_id)}
        holder -> {:taken, holder.nickname, suggestion(room, holder.nickname, person_id)}
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

  defp member(person_id, nickname) do
    %{
      id: person_id,
      nickname: nickname,
      sitting_out?: false,
      blind?: false,
      left?: false,
      removed?: false
    }
  end

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

  defp holder(room, nickname, person_id) do
    wanted = String.downcase(nickname)

    Enum.find(
      room.members,
      &(holds_nickname?(room, &1, person_id) and String.downcase(&1.nickname) == wanted)
    )
  end

  defp holds_nickname?(_room, %{left?: false}, _person_id), do: true

  defp holds_nickname?(%{game: %Game{seats: seats}}, %{id: id}, person_id),
    do: id != person_id and id in seats

  defp holds_nickname?(_room, _member, _person_id), do: false

  defp suggestion(room, held, person_id) do
    base = String.replace(held, ~r/ \d+$/u, "")

    2
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(&numbered(base, &1))
    |> Enum.find(&(holder(room, &1, person_id) == nil))
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

  @spec blind(t(), person_id(), boolean()) :: {:ok, t()} | {:error, :not_member}
  def blind(room, person_id, on?) when is_boolean(on?) do
    if member?(room, person_id) do
      {:ok, update_member(room, person_id, &%{&1 | blind?: on?})}
    else
      {:error, :not_member}
    end
  end

  @spec leave(t(), person_id(), [person_id()]) :: {:ok | :roll, t()} | {:error, :not_member}
  def leave(room, id, connected) do
    if member?(room, id) do
      %{room | away: Map.delete(room.away, id)}
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
    with {:ok, id} <- other_present(room, by, n),
         do: room |> update_member(id, &%{&1 | removed?: true}) |> leave(id, connected)
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

  @spec move_seat(t(), person_id(), person_id()) :: {:moved | :ok | :roll, t()}
  def move_seat(room, id, id), do: {:ok, room}

  def move_seat(room, from, to) do
    cond do
      not member?(room, from) -> {:ok, %{room | host_id: host_after_move(room, from, to)}}
      member?(room, to) -> room |> take_over(from, to) |> leave(from, [])
      true -> {:moved, room |> take_over(from, to) |> swap_seats(from, to)}
    end
  end

  defp take_over(room, from, to) do
    tally =
      case Map.pop(room.tally, from) do
        {nil, tally} -> tally
        {wins, tally} -> Map.update(tally, to, wins, &(&1 + wins))
      end

    %{
      room
      | host_id: host_after_move(room, from, to),
        tally: tally,
        handover: room.handover && handover_after_move(room.handover, from, to)
    }
  end

  defp handover_after_move(handover, from, to) do
    rename = fn
      ^from -> to
      id -> id
    end

    vote =
      handover.vote &&
        %{
          handover.vote
          | by: rename.(handover.vote.by),
            yes: handover.vote.yes |> Enum.map(rename) |> Enum.uniq()
        }

    %{handover | host: rename.(handover.host), vote: vote}
  end

  defp host_after_move(%{host_id: from}, from, to), do: to
  defp host_after_move(room, _from, _to), do: room.host_id

  defp swap_seats(room, from, to) do
    swap = fn
      ^from -> to
      ^to -> from
      id -> id
    end

    away =
      case Map.pop(room.away, from) do
        {nil, away} -> away
        {at, away} -> Map.put(away, to, at)
      end

    %{
      room
      | members: Enum.map(room.members, &%{&1 | id: swap.(&1.id)}),
        away: away,
        game: room.game && Game.move_seat(room.game, from, to),
        last: room.last && swap_last(room.last, swap)
    }
  end

  defp swap_last(last, swap) do
    %{
      last
      | placement: Enum.map(last.placement, swap),
        checks:
          Enum.map(last.checks, &%{&1 | checker: swap.(&1.checker), bidder: swap.(&1.bidder)})
    }
  end

  @spec away(t(), person_id(), integer()) :: t()
  def away(room, id, at) do
    if member?(room, id),
      do: %{room | away: Map.put_new(room.away, id, at)},
      else: room
  end

  @spec back(t(), person_id()) :: t()
  def back(room, id), do: %{room | away: Map.delete(room.away, id)}

  defp connected(room),
    do: for(%{id: id} <- present(room), not Map.has_key?(room.away, id), do: id)

  @spec settle_handover(t(), integer(), ([person_id()] -> [person_id()])) :: t()
  def settle_handover(room, now, shuffle) do
    room = %{room | handover: handover(room, now)}

    if room.handover != nil and (now >= room.handover.ends_at or vote_passes?(room)),
      do: hand_over(room, shuffle),
      else: room
  end

  defp vote_passes?(%{handover: %{vote: %{yes: yes}}} = room) do
    case voters(room) do
      [] -> false
      voters -> Enum.all?(voters, &(&1 in yes))
    end
  end

  defp vote_passes?(_room), do: false

  defp voters(room), do: connected(room) -- [room.handover.host]

  defp handover(%{host_id: id, handover: handover} = room, now) do
    cond do
      not Map.has_key?(room.away, id) -> nil
      match?(%{host: ^id}, handover) -> handover
      true -> %{host: id, ends_at: now + @handover_after, vote: nil, vote_again_at: nil}
    end
  end

  @spec hand_over(t(), ([person_id()] -> [person_id()])) :: t()
  def hand_over(%{handover: %{}} = room, shuffle) do
    case shuffle.(voters(room)) do
      [id | _] -> %{room | host_id: id, handover: nil}
      [] -> room
    end
  end

  def hand_over(room, _shuffle), do: room

  @spec start_vote(t(), person_id(), integer()) ::
          {:ok, t()} | {:error, :no_handover | :not_member | :voting | :too_soon}
  def start_vote(%{handover: nil}, _by, _now), do: {:error, :no_handover}

  def start_vote(%{handover: handover} = room, by, now) do
    cond do
      by not in connected(room) -> {:error, :not_member}
      handover.vote != nil -> {:error, :voting}
      now < (handover.vote_again_at || now) -> {:error, :too_soon}
      true -> {:ok, put_vote(room, %{by: by, yes: [by], ends_at: now + @vote_for})}
    end
  end

  @spec vote(t(), person_id(), boolean(), integer()) ::
          {:ok, t()} | {:error, :no_vote | :not_member}
  def vote(%{handover: %{vote: %{} = vote}} = room, by, yes?, now) when is_boolean(yes?) do
    cond do
      by not in connected(room) -> {:error, :not_member}
      not yes? -> {:ok, vote_failed(room, now)}
      by in vote.yes -> {:ok, room}
      true -> {:ok, put_vote(room, %{vote | yes: vote.yes ++ [by]})}
    end
  end

  def vote(_room, _by, yes?, _now) when is_boolean(yes?), do: {:error, :no_vote}

  @spec vote_over(t(), integer()) :: t()
  def vote_over(%{handover: %{vote: %{ends_at: ends_at}}} = room, now),
    do: vote_failed(room, min(now, ends_at))

  def vote_over(room, _now), do: room

  defp put_vote(room, vote), do: %{room | handover: %{room.handover | vote: vote}}

  defp vote_failed(room, now),
    do: %{room | handover: %{room.handover | vote: nil, vote_again_at: now + @vote_again_after}}

  @spec dealt_in(t()) :: [person_id()]
  def dealt_in(room) do
    for member <- present(room),
        not member.sitting_out?,
        not Map.has_key?(room.away, member.id),
        do: member.id
  end

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
  def start_round(room, dice) do
    blind = for %{blind?: true, id: id} <- room.members, do: id
    %{room | game: Game.start_round(room.game, dice, blind)}
  end

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

  @spec peek(t(), person_id()) :: {:ok, t()} | {:error, :not_bidding | :not_blind}
  def peek(%{game: nil}, _id), do: {:error, :not_bidding}

  def peek(room, id) do
    with {:ok, game} <- Game.peek(room.game, id), do: {:ok, %{room | game: game}}
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

  @spec to_save(t()) :: t()
  def to_save(room), do: %{room | game: room.game && Game.without_round(room.game)}

  @spec restore(t()) :: {:roll, t()} | {:ok, t()}
  def restore(saved) do
    room = struct(__MODULE__, Map.from_struct(saved))

    room = %{
      room
      | members: Enum.map(room.members, &Map.merge(member(&1.id, &1.nickname), &1)),
        game: room.game && struct(Game, Map.from_struct(room.game))
    }

    cond do
      room.game == nil -> {:ok, room}
      Game.over?(room.game) -> {:ok, game_over(room)}
      true -> {:roll, room}
    end
  end

  defp game_over(%{game: game} = room) do
    [winner | _] = placement = Game.placement(game)

    %{
      room
      | game: nil,
        tally: Map.update(room.tally, winner, 1, &(&1 + 1)),
        last: %{placement: placement, rounds: game.round, checks: game.checks}
    }
  end

  @spec finished(t(), t()) :: finished() | nil
  def finished(%{game: %Game{}}, %{game: nil, last: %{} = last} = room) do
    %{
      room_code: room.code,
      rounds: last.rounds,
      placement:
        for {id, place} <- Enum.with_index(last.placement, 1) do
          %{
            person_id: id,
            nickname: Enum.find(room.members, &(&1.id == id)).nickname,
            place: place
          }
        end,
      checks: last.checks
    }
  end

  def finished(_old, _new), do: nil

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
      removed?: Enum.any?(room.members, &(&1.id == person_id and &1.removed?)),
      sitting_out?: me != nil and me.sitting_out?,
      blind?: blind?(me),
      playing?: playing?(room, person_id),
      host?: host?,
      host_nickname: host && host.nickname,
      can_start?: host? and room.game == nil and dealt_in >= 2,
      dealt_in: dealt_in,
      game: room.game && game_view(room, room.game, person_id),
      spectators: spectators(room, person_id),
      away: away_view(room, person_id),
      host_away: host_away_view(room, person_id),
      over: over_view(room, person_id)
    }
  end

  defp blind?(nil), do: false
  defp blind?(member), do: member.blind?

  defp host_away_view(%{handover: nil}, _viewer), do: nil
  defp host_away_view(%{handover: %{host: viewer}}, viewer), do: nil

  defp host_away_view(%{handover: handover} = room, viewer) do
    %{
      since: room.away[handover.host],
      ends_at: handover.ends_at,
      vote: handover.vote && vote_view(room, handover.vote, viewer),
      vote_again_at: handover.vote_again_at
    }
  end

  defp vote_view(room, vote, viewer) do
    voters = voters(room)

    %{
      by: person_ref(room, vote.by, viewer),
      yes: Enum.count(voters, &(&1 in vote.yes)),
      of: length(voters),
      ends_at: vote.ends_at,
      said_yes?: viewer in vote.yes
    }
  end

  defp away_view(room, viewer) do
    for {%{id: id}, n} <- Enum.with_index(room.members, 1),
        id != viewer,
        Map.has_key?(room.away, id),
        into: %{},
        do: {n, room.away[id]}
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
      my_dice: my_dice(game, viewer),
      my_turn?: my_turn?,
      can_check?: my_turn? and game.bid != nil and game.reveal == nil,
      turn: game.turn && ref.(game.turn),
      bid: game.bid && bid_view(game, game.bid, ref),
      three_sixes?: three_sixes_unchecked?(game),
      seats: game.seats |> from_seat(viewer) |> Enum.map(&seat_view(game, &1, ref)),
      reveal: game.reveal && reveal_view(game, ref),
      voided_by: game.voided_by && ref.(game.voided_by)
    }
  end

  defp my_dice(%{reveal: %{step: step}} = game, viewer) when step >= 1, do: game.dice[viewer]
  defp my_dice(game, viewer), do: if(viewer not in game.blind, do: game.dice[viewer])

  defp three_sixes_unchecked?(%{reveal: nil, bid: bid}), do: Game.three_sixes?(bid)
  defp three_sixes_unchecked?(_game), do: false

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
      out?: out?(game, seat),
      blind?: seat in game.blind,
      peeked?: seat in game.peeked
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
      bid: bid_view(game, reveal.bid, ref),
      count: if(counted?, do: reveal.count),
      stood?: if(counted?, do: reveal.stood?),
      loser: if(penalized?, do: ref.(reveal.loser)),
      penalty: if(penalized?, do: reveal.penalty),
      knocked_out?: penalized? and reveal.loser in game.out
    }
  end

  defp bid_view(game, bid, ref),
    do: %{count: bid.count, face: bid.face, by: ref.(bid.by), blind?: game.bid_blind?}

  @spec person_ref(t(), person_id(), person_id()) :: person_ref()
  def person_ref(room, person_id, viewer) do
    {member, n} =
      room.members
      |> Enum.with_index(1)
      |> Enum.find(fn {member, _n} -> member.id == person_id end)

    %{nickname: member.nickname, me?: person_id == viewer, n: n}
  end

  defp find_member(room, person_id), do: Enum.find(present(room), &(&1.id == person_id))
end
