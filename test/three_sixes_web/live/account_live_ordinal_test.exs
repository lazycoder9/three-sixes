defmodule ThreeSixesWeb.AccountLiveOrdinalTest do
  use ExUnit.Case, async: true

  alias ThreeSixesWeb.AccountLive

  test "a Placement reads as an English ordinal, the teens included" do
    for {place, ordinal} <- [
          {1, "1st"},
          {2, "2nd"},
          {3, "3rd"},
          {4, "4th"},
          {10, "10th"},
          {11, "11th"},
          {12, "12th"},
          {13, "13th"},
          {21, "21st"},
          {22, "22nd"},
          {23, "23rd"},
          {30, "30th"},
          {111, "111th"},
          {101, "101st"}
        ] do
      assert AccountLive.ordinal(place) == ordinal
    end
  end
end
