{:ok, _} = ThreeSixes.Dice.Scripted.start_link()
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(ThreeSixes.Repo, :manual)
