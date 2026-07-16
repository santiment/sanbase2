defmodule Sanbase.Hyperliquid.Bbo.CoinUniverseTest do
  use ExUnit.Case, async: false

  import Mock

  alias Sanbase.Hyperliquid.Bbo.CoinUniverse

  @moduletag capture_log: true

  # Universe: perps BTC + xyz:GOLD; spot pair @107 (base token ANSEM, quote
  # USDC); ANSEM and USDC exist only as spot tokens.
  defp mock_universe(_url, opts) do
    body =
      case Keyword.fetch!(opts, :json) do
        %{type: "perpDexs"} ->
          [nil, %{"name" => "xyz"}]

        %{type: "meta", dex: "xyz"} ->
          %{"universe" => [%{"name" => "xyz:GOLD"}]}

        %{type: "meta"} ->
          %{"universe" => [%{"name" => "BTC"}]}

        %{type: "spotMeta"} ->
          %{
            "universe" => [%{"name" => "@107", "tokens" => [1, 0]}],
            "tokens" => [
              %{"name" => "USDC", "index" => 0},
              %{"name" => "ANSEM", "index" => 1}
            ]
          }
      end

    {:ok, %Req.Response{status: 200, body: body}}
  end

  describe "audit/1" do
    test "flags spot-token-only coins with the pair to map instead" do
      with_mock Req, post: &mock_universe/2 do
        result = CoinUniverse.audit(MapSet.new(["BTC", "xyz:GOLD", "@107", "ANSEM", "NOPE"]))

        assert result.unsupported == ["ANSEM", "NOPE"]
        assert result.reasons["ANSEM"] =~ "only a spot token"
        assert result.reasons["ANSEM"] =~ "@107"
        assert result.reasons["NOPE"] == "not in Hyperliquid's universe"
      end
    end

    test "perp and spot pair names are subscribable" do
      with_mock Req, post: &mock_universe/2 do
        result = CoinUniverse.audit(MapSet.new(["BTC", "xyz:GOLD", "@107"]))
        assert result.unsupported == []
        assert result.reasons == %{}
      end
    end

    test "spot token with no pair gets the no-pair reason" do
      with_mock Req, post: &mock_universe/2 do
        result = CoinUniverse.audit(MapSet.new(["USDC"]))
        assert result.reasons["USDC"] =~ "no perp market, no spot pair"
      end
    end

    test "fetch failure returns an error instead of flagging everything" do
      with_mock Req, post: fn _url, _opts -> {:error, :nxdomain} end do
        assert {:error, :nxdomain} = CoinUniverse.audit(MapSet.new(["BTC"]))
      end
    end
  end

  describe "coin_supported?/2" do
    test "valid perp and spot pair names return :ok" do
      with_mock Req, post: &mock_universe/2 do
        assert CoinUniverse.coin_supported?("BTC") == :ok
        assert CoinUniverse.coin_supported?("xyz:GOLD") == :ok
        assert CoinUniverse.coin_supported?("@107") == :ok
      end
    end

    test "spot-token-only name is unsupported with its pairs as suggestions" do
      with_mock Req, post: &mock_universe/2 do
        assert CoinUniverse.coin_supported?("ANSEM") ==
                 {:unsupported, :spot_token_only, ["@107"]}
      end
    end

    test "unknown name is unsupported with jaro suggestions" do
      with_mock Req, post: &mock_universe/2 do
        assert {:unsupported, :not_in_universe, suggestions} =
                 CoinUniverse.coin_supported?("GOLD")

        assert "xyz:GOLD" in suggestions
      end
    end
  end
end
