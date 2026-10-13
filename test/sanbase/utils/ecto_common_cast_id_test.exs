defmodule Sanbase.Utils.EctoCommonCastIdTest do
  use ExUnit.Case,
    async: true,
    parameterize:
      for(
        {input, expected} <- [
          {12, {:ok, 12}},
          {"12", {:ok, 12}},
          {"9223372036854775807", {:ok, 9_223_372_036_854_775_807}},
          {"9223372036854775808", :error},
          {"99999999999999999999", :error},
          {"12abc", :error},
          {" 12 ", :error},
          {"1.5", :error},
          {1.5, :error},
          {"abc", :error},
          {"", :error},
          {nil, :error},
          {0, :error},
          {-5, :error}
        ],
        do: %{input: input, expected: expected}
      )

  test "cast_id/1 accepts only positive bigint ids", %{input: input, expected: expected} do
    assert Sanbase.Utils.EctoCommon.cast_id(input) == expected
  end
end
