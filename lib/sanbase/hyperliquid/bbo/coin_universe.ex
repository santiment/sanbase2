defmodule Sanbase.Hyperliquid.Bbo.CoinUniverse do
  @moduledoc ~s"""
  Hyperliquid's coin universe: fetching the authoritative set of tradeable
  coins and validating/auditing the coins we subscribe to against it.

  Only Hyperliquid can say whether a coin is real. The universe spans every perp
  dex — the primary one plus each builder-deployed dex from `perpDexs`, where
  stocks, commodities, FX and other RWAs live (namespaced like `"xyz:GOLD"`) —
  and spot. No single endpoint returns all of them, so we list the dexs and
  union one `meta` request per dex with `spotMeta`.

  A name is valid for the `bbo` channel only if it is a *tradeable pair*: a
  perp name (`"BTC"`, `"xyz:GOLD"`) or a spot pair name (`"@107"`,
  `"PURR/USDC"`). Spot *token* names (`spotMeta.tokens[].name`, e.g. a bare
  `"ANSEM"`) are deliberately NOT part of the valid set — a token with no perp
  market cannot be streamed under its bare name, and subscribing it is at best
  silently ignored. Such coins are flagged with a dedicated reason and, when
  the token has spot pairs, the pair names to use instead.
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
  @spec verify_on_write?() :: boolean()
  def verify_on_write?() do
    Config.module_get(__MODULE__, :verify_on_write?)
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> Kernel.in(["true", "1"])
  end

  @doc ~s"""
  Cross-check the coins we would subscribe to against Hyperliquid's live
  universe (every perp dex plus spot). Logs and returns every coin that cannot
  be streamed over `bbo`, each with the reason — either not known to HL at
  all, or existing only as a spot token with no perp market (in which case the
  reason names the spot pair(s) to map instead, when any exist). With no
  argument it loads the `#{@source}` mappings itself, so it's safe from a
  remote console:

      Sanbase.Hyperliquid.Bbo.CoinUniverse.audit()

  Returns `%{desired: n, universe: n, unsupported: [coin, ...],
  reasons: %{coin => reason}}`, or `{:error, reason}` if the universe could
  not be fetched.
  """
  @type audit_ok :: %{
          desired: non_neg_integer(),
          universe: non_neg_integer(),
          unsupported: [String.t()],
          reasons: %{optional(String.t()) => String.t()}
        }
  @spec audit(MapSet.t(String.t()) | nil) :: audit_ok() | {:error, term()}
  def audit(desired \\ nil) do
    desired = MapSet.to_list(desired || mapped_coins())

    case fetch() do
      {:ok, %{valid: valid} = universe} ->
        unsupported = desired |> Enum.reject(&MapSet.member?(valid, &1)) |> Enum.sort()
        reasons = Map.new(unsupported, fn coin -> {coin, unsupported_reason(coin, universe)} end)

        if unsupported == [] do
          Logger.info(
            "[HyperliquidCoinUniverse] audit OK — all #{length(desired)} coins subscribable (universe=#{MapSet.size(valid)})"
          )
        else
          details = Enum.map_join(unsupported, "; ", fn coin -> "#{coin}: #{reasons[coin]}" end)

          Logger.warning(
            "[HyperliquidCoinUniverse] #{length(unsupported)}/#{length(desired)} coin(s) not subscribable over bbo (universe=#{MapSet.size(valid)}): #{details}"
          )
        end

        %{
          desired: length(desired),
          universe: MapSet.size(valid),
          unsupported: unsupported,
          reasons: reasons
        }

      {:error, reason} = error ->
        Logger.warning(
          "[HyperliquidCoinUniverse] failed to fetch HL universe: #{inspect(reason)}"
        )

        error
    end
  end

  defp unsupported_reason(coin, %{spot_tokens: spot_tokens, token_pairs: token_pairs}) do
    if MapSet.member?(spot_tokens, coin) do
      case Map.get(token_pairs, coin, []) do
        [] ->
          "only a spot token on HL (no perp market, no spot pair) — bbo cannot stream it"

        pairs ->
          "only a spot token on HL (no perp market) — bbo needs a pair name, " <>
            "map it as: #{Enum.join(Enum.take(pairs, @suggestion_limit), ", ")}"
      end
    else
      "not in Hyperliquid's universe"
    end
  end

  @doc ~s"""
  Verify a single coin against Hyperliquid's live universe, bounded by
  `timeout` ms. Meant for the mapping-creation path.

  Returns:
    * `:ok` — coin is a bbo-subscribable name (perp or spot pair).
    * `{:unsupported, :spot_token_only, suggestions}` — HL knows the name only
      as a spot token with no perp market; `suggestions` are the spot pair
      names to map instead (possibly empty).
    * `{:unsupported, :not_in_universe, suggestions}` — HL does not know this
      name at all; `suggestions` are the closest known names (Jaro), possibly
      empty.
    * `:unverified` — HL could not be reached in time (timeout / fetch error);
      caller should allow the write but warn.
  """
  @spec coin_supported?(String.t(), non_neg_integer()) ::
          :ok
          | {:unsupported, :spot_token_only | :not_in_universe, [String.t()]}
          | :unverified
  def coin_supported?(coin, timeout \\ @verify_timeout) when is_binary(coin) do
    # async_nolink: a crash inside fetch/0 must degrade to :unverified, not
    # take down the caller (a changeset validation) with it.
    task = Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn -> fetch() end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, %{valid: valid, spot_tokens: spot_tokens, token_pairs: token_pairs}}} ->
        cond do
          MapSet.member?(valid, coin) ->
            :ok

          MapSet.member?(spot_tokens, coin) ->
            pairs = Map.get(token_pairs, coin, []) |> Enum.take(@suggestion_limit)
            {:unsupported, :spot_token_only, pairs}

          true ->
            {:unsupported, :not_in_universe, closest_coins(coin, valid)}
        end

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

  # The categorized universe:
  #   valid       — names the bbo channel accepts: perp names from every dex
  #                 (primary + each builder dex from `perpDexs`, which lists
  #                 the primary as `null` and builder dexs as maps with a
  #                 "name") plus spot PAIR names ("@107", "PURR/USDC").
  #   spot_tokens — spot token names ("PURR"); NOT valid for bbo, tracked so
  #                 a token-only mapping gets a precise reason.
  #   token_pairs — %{token name => [spot pair names it is the base of]}, for
  #                 "map it as @107 instead" suggestions.
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

      # Order is preserved by Task.async_stream, so results align with
      # [spotMeta | meta_requests].
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
        [{:ok, spot_body} | meta_oks] = results
        perp_names = Enum.flat_map(meta_oks, fn {:ok, body} -> universe_names(body) end)

        {:ok,
         %{
           valid: MapSet.new(perp_names ++ universe_names(spot_body)),
           spot_tokens: MapSet.new(token_names(spot_body)),
           token_pairs: token_pair_map(spot_body)
         }}
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

  # Tradeable pair names in a `meta`/`spotMeta` body: `universe[].name`
  # (perp names or spot pair names, depending on the endpoint).
  defp universe_names(body), do: names_at(body, "universe")

  # Spot token names (`spotMeta.tokens[].name`) — deliberately kept separate
  # from the valid set; see the moduledoc.
  defp token_names(body), do: names_at(body, "tokens")

  defp names_at(body, key) when is_map(body) do
    case Map.get(body, key) do
      list when is_list(list) -> for %{"name" => name} <- list, is_binary(name), do: name
      _ -> []
    end
  end

  defp names_at(_, _), do: []

  # %{token name => [spot pair names]} for pairs where the token is the BASE
  # (`universe[].tokens` is `[base_index, quote_index]`), so an unsupported
  # bare token can be reported with the pair name(s) to map instead.
  defp token_pair_map(body) when is_map(body) do
    index_to_name =
      for %{"name" => name, "index" => index} <- Map.get(body, "tokens", []) |> List.wrap(),
          is_binary(name) and is_integer(index),
          into: %{},
          do: {index, name}

    Map.get(body, "universe", [])
    |> List.wrap()
    |> Enum.reduce(%{}, fn
      %{"name" => pair, "tokens" => [base, _quote]}, acc when is_binary(pair) ->
        case Map.get(index_to_name, base) do
          nil -> acc
          token -> Map.update(acc, token, [pair], &(&1 ++ [pair]))
        end

      _, acc ->
        acc
    end)
  end

  defp token_pair_map(_), do: %{}
end
