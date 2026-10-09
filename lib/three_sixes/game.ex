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
    out: []
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
  @type t :: %__MODULE__{
          seats: [person_id()],
          counts: %{person_id() => pos_integer()},
          round: non_neg_integer(),
          dice: %{person_id() => [face()]},
          bid: placed_bid() | nil,
          said: %{person_id() => bid()},
          turn: person_id() | nil,
          reveal: reveal() | nil,
          out: [person_id()]
        }

  @spec new([person_id()]) :: t()
  def new(seats), do: %__MODULE__{seats: seats, counts: Map.new(seats, &{&1, 1})}

  @spec start_round(t(), %{person_id() => [face()]}) :: t()
  def start_round(game, dice) do
    %{
      game
      | round: game.round + 1,
        dice: dice,
        bid: nil,
        said: %{},
        turn: opener(game),
        reveal: nil
    }
  end

  defp opener(%{reveal: %{loser: loser}} = game) do
    if loser in game.out, do: next_seat(game, loser), else: loser
  end

  defp opener(game), do: hd(game.seats)

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
    game = update_in(game.counts[loser], &(&1 + 1))
    if game.counts[loser] == @knocked_out_at, do: %{game | out: game.out ++ [loser]}, else: game
  end

  defp bidding?(game), do: game.turn != nil and game.reveal == nil

  defp next_seat(game, seat) do
    {before, [^seat | rest]} = Enum.split_while(game.seats, &(&1 != seat))
    Enum.find(rest ++ before, &(&1 not in game.out))
  end

  @spec offers(bid() | nil, non_neg_integer(), integer()) :: [map()]
  def offers(bid, dice_on_table, step),
    do: higher_faces(bid) ++ more_dice(bid, dice_on_table, step)

  defp higher_faces(%{face: face} = bid) when face < 6,
    do: [%{count: bid.count, faces: Enum.to_list((face + 1)..6)}]

  defp higher_faces(_bid), do: []

  defp more_dice(bid, dice_on_table, step) do
    least = if bid, do: bid.count + 1, else: 1
    count = least + (step |> min(dice_on_table - least) |> max(0))

    if least > dice_on_table do
      []
    else
      [
        %{
          count: count,
          faces: Enum.to_list(1..6),
          step?: dice_on_table > least,
          at_max?: count == dice_on_table
        }
      ]
    end
  end
end
