defmodule ThreeSixes.Game do
  @enforce_keys [:seats, :counts]
  defstruct [
    :seats,
    :counts,
    round: 0,
    dice: %{},
    bid: nil,
    said: %{},
    turn: nil,
    reveal: nil,
    opener: nil,
    out: [],
    voided_by: nil,
    checks: []
  ]

  @knocked_out_at 6

  @type person_id :: String.t()
  @type face :: 1..6
  @type bid :: %{count: pos_integer(), face: face()}
  @type placed_bid :: %{count: pos_integer(), face: face(), by: person_id()}
  @type reveal :: %{
          bid: placed_bid(),
          checker: person_id(),
          count: non_neg_integer(),
          stood?: boolean(),
          loser: person_id(),
          step: 0..3
        }
  @type check :: %{
          round: pos_integer(),
          checker: person_id(),
          bidder: person_id(),
          stood?: boolean()
        }
  @type t :: %__MODULE__{
          seats: [person_id()],
          counts: %{person_id() => pos_integer()},
          round: non_neg_integer(),
          dice: %{person_id() => [face()]},
          bid: placed_bid() | nil,
          said: %{person_id() => bid()},
          turn: person_id() | nil,
          reveal: reveal() | nil,
          opener: person_id() | nil,
          out: [person_id()],
          voided_by: person_id() | nil,
          checks: [check()]
        }

  @spec new([person_id()]) :: t()
  def new(seats), do: %__MODULE__{seats: seats, counts: Map.new(seats, &{&1, 1})}

  @spec start_round(t(), %{person_id() => [face()]}) :: t()
  def start_round(game, dice) do
    opener = opener(game)

    %{
      game
      | round: game.round + 1,
        dice: dice,
        bid: nil,
        said: %{},
        turn: opener,
        reveal: nil,
        opener: opener,
        voided_by: if(game.reveal, do: nil, else: game.voided_by)
    }
  end

  defp opener(%{reveal: %{loser: loser}} = game), do: in_play_from(game, loser)
  defp opener(%{voided_by: leaver} = game) when leaver != nil, do: next_seat(game, leaver)
  defp opener(%{opener: opener} = game) when opener != nil, do: in_play_from(game, opener)
  defp opener(game), do: hd(game.seats)

  defp in_play_from(game, seat), do: if(seat in game.out, do: next_seat(game, seat), else: seat)

  @spec without_round(t()) :: t()
  def without_round(game) do
    %{
      game
      | dice: %{},
        bid: nil,
        said: %{},
        turn: nil,
        reveal: nil,
        opener: next_opener(game),
        voided_by: nil
    }
  end

  defp next_opener(%{reveal: %{step: 3}} = game), do: opener(game)
  defp next_opener(game), do: game.opener

  @spec to_roll(t()) :: [{person_id(), pos_integer()}]
  def to_roll(game), do: Enum.map(in_play(game), &{&1, game.counts[&1]})

  @spec dice_on_table(t()) :: non_neg_integer()
  def dice_on_table(game), do: game |> in_play() |> Enum.map(&game.counts[&1]) |> Enum.sum()

  defp in_play(game), do: game.seats -- game.out

  @spec over?(t()) :: boolean()
  def over?(game), do: match?([_winner], in_play(game))

  @spec placement(t()) :: [person_id()]
  def placement(game) do
    [winner] = in_play(game)
    [winner | Enum.reverse(game.out)]
  end

  @spec min_count(bid() | nil, face()) :: pos_integer()
  def min_count(nil, _face), do: 1
  def min_count(bid, face) when face > bid.face, do: bid.count
  def min_count(bid, _face), do: bid.count + 1

  @spec legal_raise?(bid() | nil, non_neg_integer(), term(), term()) :: boolean()
  def legal_raise?(bid, dice_on_table, count, face) do
    is_integer(count) and face in 1..6 and min_count(bid, face) <= count and
      count <= dice_on_table
  end

  @spec raise(t(), person_id(), term(), term()) ::
          {:ok, t()} | {:error, :not_bidding | :not_your_turn | :illegal}
  def raise(game, by, count, face) do
    cond do
      not bidding?(game) -> {:error, :not_bidding}
      game.turn != by -> {:error, :not_your_turn}
      not legal_raise?(game.bid, dice_on_table(game), count, face) -> {:error, :illegal}
      true -> {:ok, raised(game, by, count, face)}
    end
  end

  defp raised(game, by, count, face) do
    %{
      game
      | bid: %{count: count, face: face, by: by},
        said: Map.put(game.said, by, %{count: count, face: face}),
        turn: next_seat(game, by)
    }
  end

  @spec check(t(), person_id()) ::
          {:ok, t()} | {:error, :not_bidding | :not_your_turn | :no_bid}
  def check(game, by) do
    cond do
      not bidding?(game) -> {:error, :not_bidding}
      game.turn != by -> {:error, :not_your_turn}
      game.bid == nil -> {:error, :no_bid}
      true -> {:ok, checked(game, by)}
    end
  end

  defp checked(%{bid: bid} = game, by) do
    count = game.dice |> Map.values() |> List.flatten() |> Enum.count(&(&1 == bid.face))
    stood? = count >= bid.count

    reveal = %{
      bid: bid,
      checker: by,
      count: count,
      stood?: stood?,
      loser: if(stood?, do: by, else: bid.by),
      step: 0
    }

    %{game | turn: nil, reveal: reveal}
  end

  @spec advance_reveal(t(), 1..3) :: t()
  def advance_reveal(%{reveal: %{step: at}} = game, step) when step > at do
    game = put_in(game.reveal.step, step)
    if step == 3, do: penalize(game, game.reveal.loser), else: game
  end

  def advance_reveal(game, _step), do: game

  defp penalize(game, loser) do
    game = %{
      game
      | counts: Map.update!(game.counts, loser, &(&1 + 1)),
        checks: game.checks ++ [check_of(game)]
    }

    if game.counts[loser] == @knocked_out_at and loser not in game.out,
      do: %{game | out: game.out ++ [loser]},
      else: game
  end

  defp check_of(%{reveal: reveal} = game) do
    %{round: game.round, checker: reveal.checker, bidder: reveal.bid.by, stood?: reveal.stood?}
  end

  defp bidding?(game), do: game.turn != nil and game.reveal == nil

  defp next_seat(game, seat) do
    {before, [^seat | rest]} = Enum.split_while(game.seats, &(&1 != seat))
    Enum.find(rest ++ before, &(&1 not in game.out))
  end

  @spec leave(t(), person_id()) :: {:ok, t()} | {:void, t()} | {:over, t()}
  def leave(game, id) do
    cond do
      id not in in_play(game) -> {:ok, game}
      over?(game) -> {:over, game}
      true -> knock_out(%{game | out: game.out ++ [id]}, id)
    end
  end

  defp knock_out(game, id) do
    cond do
      over?(game) -> {:over, keep_unsettled_check(game)}
      game.reveal != nil -> {:ok, game}
      true -> {:void, void(game, id)}
    end
  end

  defp keep_unsettled_check(%{reveal: %{step: step}} = game) when step < 3,
    do: %{game | checks: game.checks ++ [check_of(game)]}

  defp keep_unsettled_check(game), do: game

  defp void(game, leaver),
    do: %{game | turn: nil, bid: nil, said: %{}, dice: %{}, reveal: nil, voided_by: leaver}

  @spec move_seat(t(), person_id(), person_id()) :: t()
  def move_seat(game, from, to) do
    swap = fn
      ^from -> to
      ^to -> from
      id -> id
    end

    %{
      game
      | seats: Enum.map(game.seats, swap),
        counts: swap_keys(game.counts, swap),
        dice: swap_keys(game.dice, swap),
        said: swap_keys(game.said, swap),
        turn: swap.(game.turn),
        opener: swap.(game.opener),
        out: Enum.map(game.out, swap),
        voided_by: swap.(game.voided_by),
        bid: game.bid && %{game.bid | by: swap.(game.bid.by)},
        reveal: game.reveal && swap_reveal(game.reveal, swap),
        checks: Enum.map(game.checks, &swap_check(&1, swap))
    }
  end

  defp swap_keys(map, swap), do: Map.new(map, fn {id, value} -> {swap.(id), value} end)

  defp swap_reveal(reveal, swap) do
    %{
      reveal
      | checker: swap.(reveal.checker),
        loser: swap.(reveal.loser),
        bid: %{reveal.bid | by: swap.(reveal.bid.by)}
    }
  end

  defp swap_check(check, swap),
    do: %{check | checker: swap.(check.checker), bidder: swap.(check.bidder)}

  @type offer :: %{count: pos_integer(), faces: [face()], stepped?: boolean()}

  @spec offers(bid() | nil, non_neg_integer(), integer()) :: [offer()]
  def offers(bid, dice_on_table, step),
    do: higher_faces(bid) ++ stepped(bid, dice_on_table, step)

  @spec max_step(bid() | nil, non_neg_integer()) :: non_neg_integer()
  def max_step(bid, dice_on_table), do: max(dice_on_table - least(bid) - 1, 0)

  @spec cheapest_offer(bid() | nil, non_neg_integer(), integer(), face()) ::
          {pos_integer(), face()} | nil
  def cheapest_offer(bid, dice_on_table, step, face) do
    stepped? = clamp(bid, dice_on_table, step) > 0
    rows = offers(bid, dice_on_table, step)

    case Enum.find(rows, &(face in &1.faces and (&1.stepped? or not stepped?))) do
      %{count: count} -> {count, face}
      nil -> nil
    end
  end

  defp higher_faces(%{face: face} = bid) when face < 6,
    do: [%{count: bid.count, faces: Enum.to_list((face + 1)..6), stepped?: false}]

  defp higher_faces(_bid), do: []

  defp stepped(bid, dice_on_table, step) do
    first = least(bid) + clamp(bid, dice_on_table, step)

    for count <- first..(first + 1)//1,
        count <= dice_on_table,
        do: %{count: count, faces: Enum.to_list(1..6), stepped?: true}
  end

  defp clamp(bid, dice_on_table, step), do: step |> min(max_step(bid, dice_on_table)) |> max(0)

  defp least(nil), do: 1
  defp least(bid), do: bid.count + 1
end
