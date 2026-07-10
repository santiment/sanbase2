defmodule Sanbase.Hyperliquid.Bbo.CoinUniverse do
  @moduledoc ~s"""
  Hyperliquid's coin universe: fetching the authoritative set of tradeable
  coins and validating/auditing the coins we subscribe to against it.

  Only Hyperliquid can say whether a coin is real. The universe spans every perp
  dex — the primary one plus each builder-deployed dex from `perpDexs`, where
  stocks, commodities, FX and other RWAs live (namespaced like `"xyz:GOLD"`) —
  and spot. No single endpoint returns all of them, so we list the dexs and
  union one `meta` request per dex with `spotMeta`.
  """

  require Logger

  alias Sanbase.Project.SourceSlugMapping
  alias Sanbase.Utils.Config

  @source "hyperliquid"
  @info_url "https://api.hyperliquid.xyz/info"

  # Upper bound on how long a synchronous single-coin verification (used when a
  # mapping is created) may block before we give up and let the insert through.
  @verify_timeout 5_000
  # Jaro-distance threshold and cap for "did you mean" suggestions.
  @suggestion_threshold 0.8
  @suggestion_limit 3
  # Stocks/commodities/FX live on the builder dex "xyz" (e.g. "xyz:GOLD"), so a
  # bare "GOLD" should still surface "xyz:GOLD" as a suggestion.
  @rwa_dex_prefix "xyz:"
  # Per-dex `meta`/`spotMeta` requests are fetched concurrently, each bounded so
  # a single slow dex can't blow the caller's verification budget.
  @universe_fetch_concurrency 16
  @universe_fetch_timeout 4_000

  @doc ~s"""
  Whether creating/editing a `#{@source}` source-slug mapping should be verified
  against HL's live universe (a synchronous HTTP call). Off in tests so the
  suite never reaches out to Hyperliquid.
  """
  def verify_on_write?() do
    Config.module_get(__MODULE__, :verify_on_write?)
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> Kernel.in(["true", "1"])
  end

  @doc ~s"""
  Cross-check the coins we would subscribe to against Hyperliquid's live
  universe (every perp dex plus spot). Logs and returns every coin HL does not
  know about — the authoritative "bad coin" list. With no argument it loads the
  `#{@source}` mappings itself, so it's safe from a remote console:

      Sanbase.Hyperliquid.Bbo.CoinUniverse.audit()

  Returns `%{desired: n, universe: n, unsupported: [coin, ...]}`, or
  `{:error, reason}` if the universe could not be fetched.
  """
  def audit(desired \\ nil) do
    desired = MapSet.to_list(desired || mapped_coins())

    case fetch() do
      {:ok, universe} ->
        unsupported = desired |> Enum.reject(&MapSet.member?(universe, &1)) |> Enum.sort()

        if unsupported == [] do
          Logger.info(
            "[HyperliquidCoinUniverse] audit OK — all #{length(desired)} coins present (universe=#{MapSet.size(universe)})"
          )
        else
          Logger.warning(
            "[HyperliquidCoinUniverse] #{length(unsupported)}/#{length(desired)} coin(s) NOT in HL universe (universe=#{MapSet.size(universe)}): #{inspect(unsupported)}"
          )
        end

        %{desired: length(desired), universe: MapSet.size(universe), unsupported: unsupported}

      {:error, reason} = error ->
        Logger.warning(
          "[HyperliquidCoinUniverse] failed to fetch HL universe: #{inspect(reason)}"
        )

        error
    end
  end

  @doc ~s"""
  Verify a single coin against Hyperliquid's live universe, bounded by
  `timeout` ms. Meant for the mapping-creation path.

  Returns:
    * `:ok` — coin exists in the HL universe.
    * `{:unsupported, suggestions}` — HL was reached and does not know this
      coin; `suggestions` are the closest known names (Jaro), possibly empty.
    * `:unverified` — HL could not be reached in time (timeout / fetch error);
      caller should allow the write but warn.
  """
  @spec coin_supported?(String.t(), non_neg_integer()) ::
          :ok | {:unsupported, [String.t()]} | :unverified
  def coin_supported?(coin, timeout \\ @verify_timeout) when is_binary(coin) do
    task = Task.async(fn -> fetch() end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, universe}} ->
        if MapSet.member?(universe, coin),
          do: :ok,
          else: {:unsupported, closest_coins(coin, universe)}

      _ ->
        :unverified
    end
  end

  defp mapped_coins() do
    @source
    |> SourceSlugMapping.get_source_slug_mappings(return: :all)
    |> Enum.map(fn {coin, _slug} -> coin end)
    |> MapSet.new()
  end

  # Closest known coin names to `coin` by Jaro distance, for a "did you mean"
  # hint. Case-insensitive; each candidate is scored by the better of the raw
  # input and the input namespaced under the RWA dex, so a bare "GOLD" surfaces
  # "xyz:GOLD" (exact prefixed match scores 1.0).
  defp closest_coins(coin, universe) do
    target = String.upcase(coin)
    prefixed = String.upcase(@rwa_dex_prefix <> coin)

    universe
    |> Enum.map(fn candidate ->
      up = String.upcase(candidate)
      distance = max(String.jaro_distance(target, up), String.jaro_distance(prefixed, up))
      {candidate, distance}
    end)
    |> Enum.filter(fn {_candidate, distance} -> distance >= @suggestion_threshold end)
    |> Enum.sort_by(fn {_candidate, distance} -> distance end, :desc)
    |> Enum.take(@suggestion_limit)
    |> Enum.map(fn {candidate, _distance} -> candidate end)
  end

  # The full set of coins the bbo channel accepts, unioned across every perp dex
  # (primary + each builder dex from `perpDexs`, which lists the primary as
  # `null` and builder dexs as maps with a "name") and spot.
  #
  # EVERY request must succeed — a partial fetch would omit part of the universe
  # and wrongly flag real coins as unsupported (blocking valid mapping creates
  # and unsubscribing live coins). On any failure we return an error so callers
  # treat it as "could not verify" rather than "empty universe".
  defp fetch() do
    with {:ok, dexs} <- info_request(%{type: "perpDexs"}) do
      meta_requests =
        Enum.map(List.wrap(dexs), fn
          %{"name" => name} when is_binary(name) -> %{type: "meta", dex: name}
          _ -> %{type: "meta"}
        end)

      results =
        [%{type: "spotMeta"} | meta_requests]
        |> Task.async_stream(&info_request/1,
          max_concurrency: @universe_fetch_concurrency,
          timeout: @universe_fetch_timeout,
          on_timeout: :kill_task
        )
        |> Enum.map(fn
          {:ok, result} -> result
          _ -> {:error, :timeout}
        end)

      if Enum.all?(results, &match?({:ok, _}, &1)) do
        {:ok, results |> Enum.flat_map(fn {:ok, body} -> coin_names(body) end) |> MapSet.new()}
      else
        {:error, :incomplete_universe}
      end
    end
  end

  # `meta`/`spotMeta` return a JSON object; `perpDexs` returns a JSON array —
  # accept both as success.
  defp info_request(payload) do
    case Req.post(@info_url, json: payload, receive_timeout: 10_000, retry: :transient) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) or is_list(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Coin names in a `meta`/`spotMeta` body: `universe[].name` (perp or spot) plus
  # spot `tokens[].name`.
  defp coin_names(body) when is_map(body) do
    Enum.flat_map(["universe", "tokens"], fn key ->
      case Map.get(body, key) do
        list when is_list(list) -> for %{"name" => name} <- list, is_binary(name), do: name
        _ -> []
      end
    end)
  end

  defp coin_names(_), do: []
end
