defmodule Sanbase.Hyperliquid.Bbo.WebsocketScraperTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory

  alias Sanbase.Hyperliquid.Bbo.Quarantine
  alias Sanbase.Hyperliquid.Bbo.WebsocketScraper

  @topic "hyperliquid_bbo_prices"
  @exporter :hyperliquid_bbo_exporter

  # Overrides for these keys build the Quarantine struct inside the state.
  @quarantine_keys [
    :probation,
    :probing,
    :probe_strikes,
    :quarantined,
    :audit_excluded,
    :recent_sends
  ]

  setup do
    Sanbase.InMemoryKafka.Producer.clear_state()

    start_supervised!(
      Sanbase.KafkaExporter.child_spec(
        id: @exporter,
        name: @exporter,
        topic: @topic,
        buffering_max_messages: 10_000,
        can_send_after_interval: 0,
        kafka_flush_timeout: 60_000
      )
    )

    :ok
  end

  defp build_state(overrides \\ []) do
    {q_overrides, rest} = overrides |> Map.new() |> Map.split(@quarantine_keys)

    %{
      active_subs: MapSet.new(),
      slug_map: %{},
      pending_sub_queue: :queue.new(),
      last_emitted: %{},
      coalesce_buffer: %{},
      reconnect_backoff_ms: 1000,
      last_message_time: System.system_time(:millisecond),
      healthcheck_failures: 0,
      coalesce_window_ms: 1000,
      timers: %{},
      quarantine: struct!(Quarantine, q_overrides)
    }
    |> Map.merge(rest)
  end

  defp sub_send(coin, ms_ago) do
    %{coin: coin, slugs: [], sent_at_ms: System.monotonic_time(:millisecond) - ms_ago}
  end

  defp side(px, sz), do: %{"px" => to_string(px), "sz" => to_string(sz), "n" => 1}

  defp bbo_frame(coin, time_ms, bid, ask) do
    json =
      Jason.encode!(%{
        "channel" => "bbo",
        "data" => %{"coin" => coin, "time" => time_ms, "bbo" => [bid, ask]}
      })

    {:text, json}
  end

  defp drain_topic() do
    Sanbase.KafkaExporter.flush(@exporter)
    Sanbase.InMemoryKafka.Producer.get_state() |> Map.get(@topic, [])
  end

  defp put_enabled(value) do
    cur = Application.get_env(:sanbase, WebsocketScraper, [])
    Application.put_env(:sanbase, WebsocketScraper, Keyword.put(cur, :enabled?, value))
  end

  describe "bbo frame -> Kafka" do
    test "mapped coin emits Kafka tuple with coin and seeded slug" do
      state = build_state(slug_map: %{"BTC" => ["bitcoin"]})

      {:ok, _state} =
        WebsocketScraper.handle_frame(
          bbo_frame("BTC", 1_700_000_000_000, side(62000, 1.5), side(62001, 2.0)),
          state
        )

      assert [{key, json}] = drain_topic()
      assert key == "hyperliquid_bbo_bitcoin_1700000000000"

      assert %{
               "slug" => "bitcoin",
               "coin" => "BTC",
               "timestamp_ms" => 1_700_000_000_000,
               "bid_price" => 62000.0,
               "bid_volume" => 1.5,
               "ask_price" => 62001.0,
               "ask_volume" => 2.0
             } = Jason.decode!(json)
    end

    test "unmapped coin is dropped" do
      state = build_state(slug_map: %{"BTC" => ["bitcoin"]})

      {:ok, _state} =
        WebsocketScraper.handle_frame(
          bbo_frame("ETH", 1_700_000_000_000, side(2500, 10), side(2501, 5)),
          state
        )

      assert drain_topic() == []
    end

    test "one-sided book emits row with the missing side null" do
      state = build_state(slug_map: %{"BTC" => ["bitcoin"]})

      {:ok, _state} =
        WebsocketScraper.handle_frame(
          bbo_frame("BTC", 1_700_000_000_000, side(62000, 1.5), nil),
          state
        )

      assert [{_key, json}] = drain_topic()
      decoded = Jason.decode!(json)
      assert decoded["bid_price"] == 62000.0
      assert decoded["bid_volume"] == 1.5
      assert decoded["ask_price"] == nil
      assert decoded["ask_volume"] == nil
    end

    test "malformed side is rejected atomically (no partial price/volume export)" do
      state = build_state(slug_map: %{"BTC" => ["bitcoin"]})

      # Parseable price but garbage volume: the whole bid side must be nil,
      # and since the ask is missing too, nothing is exported.
      {:ok, _state} =
        WebsocketScraper.handle_frame(
          bbo_frame("BTC", 1_700_000_000_000, %{"px" => "62000", "sz" => "bad", "n" => 1}, nil),
          state
        )

      assert drain_topic() == []
    end

    test "both sides null is skipped" do
      state = build_state(slug_map: %{"BTC" => ["bitcoin"]})

      {:ok, new_state} =
        WebsocketScraper.handle_frame(
          bbo_frame("BTC", 1_700_000_000_000, nil, nil),
          state
        )

      assert drain_topic() == []
      assert new_state.last_emitted == %{}
      assert new_state.coalesce_buffer == %{}
    end

    test "multi-slug fanout: one coin -> N slugs emits N Kafka rows" do
      state = build_state(slug_map: %{"BTC" => ["bitcoin", "wbtc"]})

      {:ok, _state} =
        WebsocketScraper.handle_frame(
          bbo_frame("BTC", 1_700_000_000_000, side(62000, 1.5), side(62001, 2.0)),
          state
        )

      rows = drain_topic()
      assert length(rows) == 2

      slugs = rows |> Enum.map(fn {_k, json} -> Jason.decode!(json)["slug"] end) |> Enum.sort()
      assert slugs == ["bitcoin", "wbtc"]
    end
  end

  describe "coalescing" do
    test "single quiet-pair frame emits immediately" do
      state = build_state(slug_map: %{"BTC" => ["bitcoin"]}, coalesce_window_ms: 1000)

      {:ok, new_state} =
        WebsocketScraper.handle_frame(
          bbo_frame("BTC", 1_700_000_000_000, side(62000, 1.5), side(62001, 2.0)),
          state
        )

      assert length(drain_topic()) == 1
      assert Map.has_key?(new_state.last_emitted, "BTC")
      assert new_state.coalesce_buffer == %{}
    end

    test "burst within window: 1 immediate emit + buffered latest" do
      slug_map = %{"BTC" => ["bitcoin"]}
      state = build_state(slug_map: slug_map, coalesce_window_ms: 1000)

      # First frame: immediate emit
      {:ok, state} =
        WebsocketScraper.handle_frame(
          bbo_frame("BTC", 1_700_000_000_000, side(62000, 1.0), side(62001, 1.0)),
          state
        )

      # Subsequent frames within window: buffered (latest wins)
      {:ok, state} =
        WebsocketScraper.handle_frame(
          bbo_frame("BTC", 1_700_000_000_100, side(62002, 1.0), side(62003, 1.0)),
          state
        )

      {:ok, state} =
        WebsocketScraper.handle_frame(
          bbo_frame("BTC", 1_700_000_000_200, side(62004, 1.0), side(62005, 1.0)),
          state
        )

      {:ok, state} =
        WebsocketScraper.handle_frame(
          bbo_frame("BTC", 1_700_000_000_300, side(62006, 1.0), side(62007, 1.0)),
          state
        )

      {:ok, state} =
        WebsocketScraper.handle_frame(
          bbo_frame("BTC", 1_700_000_000_400, side(62008, 1.0), side(62009, 1.0)),
          state
        )

      # Only 1 emit so far
      assert length(drain_topic()) == 1
      Sanbase.InMemoryKafka.Producer.clear_state()

      # Last buffered frame retained
      assert state.coalesce_buffer["BTC"].bid_price == 62008.0
      assert state.coalesce_buffer["BTC"].ask_price == 62009.0

      # Force the window to have elapsed by backdating last_emitted
      now = System.system_time(:millisecond)
      state = put_in(state.last_emitted["BTC"], now - 2_000)

      {:ok, state} = WebsocketScraper.handle_info(:flush_coalesced, state)

      [{_key, json}] = drain_topic()
      decoded = Jason.decode!(json)
      assert decoded["bid_price"] == 62008.0
      assert decoded["ask_price"] == 62009.0
      assert decoded["timestamp_ms"] == 1_700_000_000_400
      assert state.coalesce_buffer == %{}
    end

    test "timestamp_ms equals frame data.time for both immediate and buffer-flushed emits" do
      slug_map = %{"BTC" => ["bitcoin"]}
      state = build_state(slug_map: slug_map, coalesce_window_ms: 1000)

      {:ok, state} =
        WebsocketScraper.handle_frame(
          bbo_frame("BTC", 1_700_000_000_000, side(62000, 1.0), side(62001, 1.0)),
          state
        )

      [{_, json}] = drain_topic()
      assert Jason.decode!(json)["timestamp_ms"] == 1_700_000_000_000
      Sanbase.InMemoryKafka.Producer.clear_state()

      {:ok, state} =
        WebsocketScraper.handle_frame(
          bbo_frame("BTC", 1_700_000_000_500, side(62100, 1.0), side(62101, 1.0)),
          state
        )

      now = System.system_time(:millisecond)
      state = put_in(state.last_emitted["BTC"], now - 2_000)

      {:ok, _state} = WebsocketScraper.handle_info(:flush_coalesced, state)

      [{_, json}] = drain_topic()
      assert Jason.decode!(json)["timestamp_ms"] == 1_700_000_000_500
    end

    test "flush drops buffered coin whose slug mapping was removed" do
      state = build_state(slug_map: %{"BTC" => ["bitcoin"]}, coalesce_window_ms: 1000)

      # First frame emits, second lands in the buffer
      {:ok, state} =
        WebsocketScraper.handle_frame(
          bbo_frame("BTC", 1_700_000_000_000, side(62000, 1.0), side(62001, 1.0)),
          state
        )

      {:ok, state} =
        WebsocketScraper.handle_frame(
          bbo_frame("BTC", 1_700_000_000_100, side(62002, 1.0), side(62003, 1.0)),
          state
        )

      assert Map.has_key?(state.coalesce_buffer, "BTC")
      assert length(drain_topic()) == 1
      Sanbase.InMemoryKafka.Producer.clear_state()

      # Mapping removed (e.g. reconcile with the coin never in active_subs),
      # window elapsed — flush must drop the entry instead of raising
      now = System.system_time(:millisecond)
      state = %{state | slug_map: %{}, last_emitted: %{"BTC" => now - 2_000}}

      {:ok, state} = WebsocketScraper.handle_info(:flush_coalesced, state)

      assert drain_topic() == []
      assert state.coalesce_buffer == %{}
    end

    test "frame after window emits immediately" do
      slug_map = %{"BTC" => ["bitcoin"]}
      state = build_state(slug_map: slug_map, coalesce_window_ms: 1000)

      now = System.system_time(:millisecond)
      state = %{state | last_emitted: %{"BTC" => now - 2_000}}

      {:ok, new_state} =
        WebsocketScraper.handle_frame(
          bbo_frame("BTC", 1_700_000_000_000, side(62000, 1.0), side(62001, 1.0)),
          state
        )

      assert length(drain_topic()) == 1
      assert new_state.last_emitted["BTC"] >= now
      assert new_state.coalesce_buffer == %{}
    end
  end

  describe "last_exported diagnostics" do
    test "immediate emit records point, export timestamp and count" do
      state = build_state(slug_map: %{"xyz:GOLD" => ["gold"]})

      {:ok, state} =
        WebsocketScraper.handle_frame(
          bbo_frame("xyz:GOLD", 1_700_000_000_000, side(4087.4, 2.8), side(4087.5, 0.01)),
          state
        )

      assert %{point: point, exported_at_ms: at, count: 1} = state.last_exported["xyz:GOLD"]
      assert point.coin == "xyz:GOLD"
      assert point.timestamp_ms == 1_700_000_000_000
      assert point.bid_price == 4087.4
      assert is_integer(at)

      # The recorded point is the one that reached Kafka
      assert [{_key, json}] = drain_topic()
      assert Jason.decode!(json)["timestamp_ms"] == 1_700_000_000_000
    end

    test "buffer flush records the flushed point and increments count" do
      state = build_state(slug_map: %{"xyz:GOLD" => ["gold"]})

      {:ok, state} =
        WebsocketScraper.handle_frame(
          bbo_frame("xyz:GOLD", 1_700_000_000_000, side(4087.4, 1.0), side(4087.5, 1.0)),
          state
        )

      # Within the window: buffered, not exported yet
      {:ok, state} =
        WebsocketScraper.handle_frame(
          bbo_frame("xyz:GOLD", 1_700_000_000_100, side(4088.0, 1.0), side(4088.1, 1.0)),
          state
        )

      assert state.last_exported["xyz:GOLD"].count == 1

      now = System.system_time(:millisecond)
      state = put_in(state.last_emitted["xyz:GOLD"], now - 2_000)

      {:ok, state} = WebsocketScraper.handle_info(:flush_coalesced, state)

      assert %{point: point, count: 2} = state.last_exported["xyz:GOLD"]
      assert point.timestamp_ms == 1_700_000_000_100
      assert point.bid_price == 4088.0
      assert state.coalesce_buffer == %{}
    end

    test "live state predating the last_exported key does not raise" do
      # Simulates a hot-recompiled process whose state lacks :last_exported
      state =
        build_state(slug_map: %{"BTC" => ["bitcoin"]})
        |> Map.delete(:last_exported)

      {:ok, state} =
        WebsocketScraper.handle_frame(
          bbo_frame("BTC", 1_700_000_000_000, side(62000, 1.0), side(62001, 1.0)),
          state
        )

      assert state.last_exported["BTC"].count == 1
    end
  end

  describe "subscription handling" do
    test "pong is ignored" do
      state = build_state()

      {:ok, new_state} =
        WebsocketScraper.handle_frame(
          {:text, Jason.encode!(%{"channel" => "pong"})},
          state
        )

      # last_message_time updates on every inbound frame, even pong
      assert new_state.last_message_time >= state.last_message_time
      assert new_state.active_subs == state.active_subs
    end

    test "subscriptionResponse updates active_subs" do
      state = build_state()

      json =
        Jason.encode!(%{
          "channel" => "subscriptionResponse",
          "data" => %{
            "method" => "subscribe",
            "subscription" => %{"type" => "bbo", "coin" => "BTC"}
          }
        })

      {:ok, state} = WebsocketScraper.handle_frame({:text, json}, state)
      assert MapSet.member?(state.active_subs, "BTC")

      json =
        Jason.encode!(%{
          "channel" => "subscriptionResponse",
          "data" => %{
            "method" => "unsubscribe",
            "subscription" => %{"type" => "bbo", "coin" => "BTC"}
          }
        })

      {:ok, state} = WebsocketScraper.handle_frame({:text, json}, state)
      refute MapSet.member?(state.active_subs, "BTC")
    end
  end

  describe "reconcile" do
    test "enqueues subscribe frames for new mappings, unsubscribe for removed" do
      btc = insert(:project, %{name: "Bitcoin", slug: "bitcoin"})
      eth = insert(:project, %{name: "Ethereum", slug: "ethereum"})

      Sanbase.Project.SourceSlugMapping.create(%{
        source: "hyperliquid",
        slug: "BTC",
        project_id: btc.id
      })

      Sanbase.Project.SourceSlugMapping.create(%{
        source: "hyperliquid",
        slug: "ETH",
        project_id: eth.id
      })

      # Already subscribed to OLD that no longer maps; ETH not yet active.
      state =
        build_state(active_subs: MapSet.new(["BTC", "OLD"]))

      {:ok, state} = WebsocketScraper.handle_info(:reconcile_subscriptions, state)

      assert state.slug_map == %{"BTC" => ["bitcoin"], "ETH" => ["ethereum"]}

      methods_by_coin =
        state.pending_sub_queue
        |> :queue.to_list()
        |> Enum.into(%{}, fn {method, coin} -> {coin, method} end)

      assert methods_by_coin == %{"ETH" => "subscribe", "OLD" => "unsubscribe"}
    end

    test "unsubscribed coin's coalesce_buffer and last_emitted entries are pruned" do
      btc = insert(:project, %{name: "Bitcoin", slug: "bitcoin"})

      Sanbase.Project.SourceSlugMapping.create(%{
        source: "hyperliquid",
        slug: "BTC",
        project_id: btc.id
      })

      state =
        build_state(
          active_subs: MapSet.new(["BTC", "DROPME"]),
          last_emitted: %{"BTC" => 100, "DROPME" => 200},
          coalesce_buffer: %{
            "BTC" => %{coin: "BTC"},
            "DROPME" => %{coin: "DROPME"}
          }
        )

      {:ok, state} = WebsocketScraper.handle_info(:reconcile_subscriptions, state)

      refute Map.has_key?(state.last_emitted, "DROPME")
      refute Map.has_key?(state.coalesce_buffer, "DROPME")
      assert Map.has_key?(state.last_emitted, "BTC")
      assert Map.has_key?(state.coalesce_buffer, "BTC")
    end
  end

  describe "flush_subs" do
    test "drains one queued entry per tick, replying with the built frame" do
      queue = :queue.in({"subscribe", "BTC"}, :queue.new())
      state = build_state(pending_sub_queue: queue)

      assert {:reply, {:text, json}, new_state} =
               WebsocketScraper.handle_info(:flush_subs, state)

      assert Jason.decode!(json) == %{
               "method" => "subscribe",
               "subscription" => %{"type" => "bbo", "coin" => "BTC"}
             }

      assert :queue.is_empty(new_state.pending_sub_queue)
    end

    test "no-op when queue is empty" do
      state = build_state()
      assert {:ok, _new_state} = WebsocketScraper.handle_info(:flush_subs, state)
    end

    test "records sent subscribes in the quarantine send log, newest first" do
      queue =
        Enum.reduce(
          [
            {"subscribe", "A"},
            {"subscribe", "B"},
            {"unsubscribe", "SKIP"},
            {"subscribe", "C"},
            {"subscribe", "D"},
            {"subscribe", "E"},
            {"subscribe", "F"}
          ],
          :queue.new(),
          &:queue.in/2
        )

      state = build_state(pending_sub_queue: queue, slug_map: %{"A" => ["a-slug"]})

      state =
        Enum.reduce(1..7, state, fn _, acc ->
          {:reply, _frame, acc} = WebsocketScraper.handle_info(:flush_subs, acc)
          acc
        end)

      recent = state.quarantine.recent_sends
      assert Enum.map(recent, & &1.coin) == ["F", "E", "D", "C", "B", "A"]
      assert Enum.all?(recent, &is_integer(&1.sent_at_ms))

      # Slugs resolved from slug_map at send time; unmapped coins get [].
      assert Enum.map(recent, & &1.slugs) == [[], [], [], [], [], ["a-slug"]]
    end

    test "the send log stores slugs from slug_map at send time" do
      queue = :queue.in({"subscribe", "BTC"}, :queue.new())

      state =
        build_state(pending_sub_queue: queue, slug_map: %{"BTC" => ["bitcoin", "btc-alias"]})

      {:reply, _frame, new_state} = WebsocketScraper.handle_info(:flush_subs, state)

      assert [%{coin: "BTC", slugs: ["bitcoin", "btc-alias"]}] = new_state.quarantine.recent_sends
    end
  end

  describe "flush_subs scheduling" do
    test "draining last frame stops the timer (no re-arm)" do
      queue = :queue.in({"subscribe", "x"}, :queue.new())
      state = build_state(pending_sub_queue: queue, timers: %{flush_subs: make_ref()})

      assert {:reply, {:text, _}, new_state} =
               WebsocketScraper.handle_info(:flush_subs, state)

      refute Map.has_key?(new_state.timers, :flush_subs)
      assert :queue.is_empty(new_state.pending_sub_queue)
    end

    test "draining when more remain re-arms the timer" do
      queue = :queue.from_list([{"subscribe", "a"}, {"unsubscribe", "b"}])
      state = build_state(pending_sub_queue: queue, timers: %{flush_subs: make_ref()})

      assert {:reply, {:text, json}, new_state} =
               WebsocketScraper.handle_info(:flush_subs, state)

      assert %{"method" => "subscribe", "subscription" => %{"coin" => "a"}} =
               Jason.decode!(json)

      assert Map.has_key?(new_state.timers, :flush_subs)
      assert :queue.len(new_state.pending_sub_queue) == 1
    end

    test "empty queue clears stale flush_subs timer ref and does not re-arm" do
      state = build_state(timers: %{flush_subs: make_ref()})

      assert {:ok, new_state} = WebsocketScraper.handle_info(:flush_subs, state)

      refute Map.has_key?(new_state.timers, :flush_subs)
    end

    test "reconcile arms flush_subs when frames are queued" do
      btc = insert(:project, %{name: "Bitcoin", slug: "bitcoin"})

      Sanbase.Project.SourceSlugMapping.create(%{
        source: "hyperliquid",
        slug: "BTC",
        project_id: btc.id
      })

      state = build_state()
      {:ok, new_state} = WebsocketScraper.handle_info(:reconcile_subscriptions, state)

      refute :queue.is_empty(new_state.pending_sub_queue)
      assert Map.has_key?(new_state.timers, :flush_subs)
    end

    test "reconcile with no-op diff does not arm flush_subs" do
      state = build_state()
      {:ok, new_state} = WebsocketScraper.handle_info(:reconcile_subscriptions, state)

      assert :queue.is_empty(new_state.pending_sub_queue)
      refute Map.has_key?(new_state.timers, :flush_subs)
    end
  end

  describe "healthcheck" do
    @describetag capture_log: true

    test "fresh last_message_time resets failure count and re-schedules" do
      state =
        build_state(
          last_message_time: System.system_time(:millisecond),
          healthcheck_failures: 3
        )

      {:ok, new_state} = WebsocketScraper.handle_info(:healthcheck, state)

      assert new_state.healthcheck_failures == 0
      assert Map.has_key?(new_state.timers, :healthcheck)
    end

    test "stale last_message_time increments failure count" do
      stale = System.system_time(:millisecond) - 120_000
      state = build_state(last_message_time: stale, healthcheck_failures: 0)

      {:ok, new_state} = WebsocketScraper.handle_info(:healthcheck, state)

      assert new_state.healthcheck_failures == 1
      assert Map.has_key?(new_state.timers, :healthcheck)
    end

    test "raises HealthcheckError once max failures exceeded" do
      stale = System.system_time(:millisecond) - 120_000
      state = build_state(last_message_time: stale, healthcheck_failures: 5)

      assert_raise WebsocketScraper.HealthcheckError, fn ->
        WebsocketScraper.handle_info(:healthcheck, state)
      end
    end
  end

  describe "handle_disconnect" do
    @describetag capture_log: true

    test "clears in-flight state, resets healthcheck failures, grows backoff" do
      state =
        build_state(
          active_subs: MapSet.new(["BTC", "ETH"]),
          pending_sub_queue: :queue.in({"subscribe", "x"}, :queue.new()),
          coalesce_buffer: %{"BTC" => %{coin: "BTC"}},
          last_emitted: %{"BTC" => 1},
          healthcheck_failures: 4,
          reconnect_backoff_ms: 1
        )

      {:reconnect, new_state} =
        WebsocketScraper.handle_disconnect(%{reason: :test}, state)

      assert new_state.active_subs == MapSet.new()
      assert :queue.is_empty(new_state.pending_sub_queue)
      assert new_state.coalesce_buffer == %{}
      assert new_state.last_emitted == %{}
      assert new_state.healthcheck_failures == 0
      assert new_state.reconnect_backoff_ms == 2
      assert new_state.prev_unconfirmed == MapSet.new()
    end

    test "short-lived connection keeps growing the backoff and clears connected_at" do
      state =
        build_state(
          connected_at: System.monotonic_time(:millisecond) - 3_000,
          reconnect_backoff_ms: 4
        )

      {:reconnect, new_state} =
        WebsocketScraper.handle_disconnect(%{reason: {:remote, :closed}}, state)

      assert new_state.reconnect_backoff_ms == 5
      assert new_state.connected_at == nil
    end
  end

  describe "probation and probing" do
    @describetag capture_log: true

    test "disconnect puts unconfirmed subscribes sent within the window on probation" do
      state =
        build_state(
          recent_sends: [sub_send("A", 100), sub_send("B", 300), sub_send("OLD", 10_000)],
          reconnect_backoff_ms: 1
        )

      {:reconnect, new_state} = WebsocketScraper.handle_disconnect(%{reason: :test}, state)

      assert new_state.quarantine.probation == ["A", "B"]
    end

    test "confirmed coins (in active_subs) never go on probation" do
      state =
        build_state(
          recent_sends: [sub_send("A", 100), sub_send("B", 300)],
          active_subs: MapSet.new(["A"]),
          reconnect_backoff_ms: 1
        )

      {:reconnect, new_state} = WebsocketScraper.handle_disconnect(%{reason: :test}, state)

      assert new_state.quarantine.probation == ["B"]
    end

    test "probation coins are not re-added and excluded coins never enter" do
      state =
        build_state(
          recent_sends: [sub_send("A", 100), sub_send("Q", 200), sub_send("X", 300)],
          probation: ["A"],
          quarantined: %{"Q" => "test reason"},
          audit_excluded: %{"X" => "audit reason"},
          reconnect_backoff_ms: 1
        )

      {:reconnect, new_state} = WebsocketScraper.handle_disconnect(%{reason: :test}, state)

      assert new_state.quarantine.probation == ["A"]
    end

    test "failed reconnect attempt (attempt_number > 1) leaves probation untouched" do
      state =
        build_state(
          recent_sends: [sub_send("B", 100)],
          probation: ["A"],
          reconnect_backoff_ms: 1
        )

      {:reconnect, new_state} =
        WebsocketScraper.handle_disconnect(%{reason: :test, attempt_number: 2}, state)

      assert new_state.quarantine.probation == ["A"]
    end

    test "probe_next starts a probe on a settled connection" do
      state =
        build_state(
          probation: ["X", "Y"],
          connected_at: System.monotonic_time(:millisecond) - 60_000
        )

      {:ok, new_state} = WebsocketScraper.handle_info(:probe_next, state)

      assert [%{coin: "X", started_ms: _}] = new_state.quarantine.probing
      assert :queue.to_list(new_state.pending_sub_queue) == [{"subscribe", "X"}]
      # Coin stays in probation until its verdict.
      assert new_state.quarantine.probation == ["X", "Y"]
      assert Map.has_key?(new_state.timers, :probe_next)
    end

    test "probe_next does not start a probe while the outbound queue drains or uptime is low" do
      draining =
        build_state(
          probation: ["X"],
          connected_at: System.monotonic_time(:millisecond) - 60_000,
          pending_sub_queue: :queue.in({"subscribe", "OTHER"}, :queue.new())
        )

      {:ok, state1} = WebsocketScraper.handle_info(:probe_next, draining)
      assert state1.quarantine.probing == []

      young =
        build_state(
          probation: ["X"],
          connected_at: System.monotonic_time(:millisecond) - 1_000
        )

      {:ok, state2} = WebsocketScraper.handle_info(:probe_next, young)
      assert state2.quarantine.probing == []
    end

    test "probe survival with confirmation clears the coin back to normal" do
      now = System.monotonic_time(:millisecond)

      state =
        build_state(
          probation: ["X", "Y"],
          probing: [%{coin: "X", started_ms: now - 20_000}],
          probe_strikes: %{"X" => 1},
          active_subs: MapSet.new(["X"])
        )

      {:ok, new_state} = WebsocketScraper.handle_info(:probe_next, state)

      assert new_state.quarantine.probing == []
      assert new_state.quarantine.probation == ["Y"]
      assert new_state.quarantine.probe_strikes == %{}
      refute Map.has_key?(new_state.quarantine.quarantined, "X")
    end

    test "probe survival without confirmation quarantines the silently-ignored coin" do
      now = System.monotonic_time(:millisecond)

      state =
        build_state(
          probation: ["X"],
          probing: [%{coin: "X", started_ms: now - 20_000}]
        )

      {:ok, new_state} = WebsocketScraper.handle_info(:probe_next, state)

      assert new_state.quarantine.probing == []
      assert new_state.quarantine.probation == []
      assert Map.get(new_state.quarantine.quarantined, "X") =~ "never confirmed"
    end

    test "crash during probe strikes; second strike convicts and quarantines" do
      now = System.monotonic_time(:millisecond)

      state =
        build_state(
          probation: ["X", "Y"],
          probing: [%{coin: "X", started_ms: now - 250}],
          reconnect_backoff_ms: 1
        )

      {:reconnect, state} = WebsocketScraper.handle_disconnect(%{reason: :test}, state)

      assert state.quarantine.probing == []
      assert state.quarantine.probe_strikes == %{"X" => 1}
      # First strike: retried after the other suspects.
      assert state.quarantine.probation == ["Y", "X"]
      refute Map.has_key?(state.quarantine.quarantined, "X")

      state = %{
        state
        | quarantine: %{
            state.quarantine
            | probing: [%{coin: "X", started_ms: System.monotonic_time(:millisecond) - 250}]
          }
      }

      {:reconnect, state} = WebsocketScraper.handle_disconnect(%{reason: :test}, state)

      assert Map.get(state.quarantine.quarantined, "X") =~ "probe conviction"
      assert state.quarantine.probation == ["Y"]
      assert state.quarantine.probe_strikes == %{}
    end

    test "crash long after the probe subscribe is not attributed to it" do
      now = System.monotonic_time(:millisecond)

      state =
        build_state(
          probation: ["X"],
          probing: [%{coin: "X", started_ms: now - 60_000}],
          reconnect_backoff_ms: 1
        )

      {:reconnect, new_state} = WebsocketScraper.handle_disconnect(%{reason: :test}, state)

      assert new_state.quarantine.probing == []
      assert new_state.quarantine.probe_strikes == %{}
      assert new_state.quarantine.probation == ["X"]
    end

    test "coin unconfirmed across two reconcile rounds moves to probation instead of re-queueing" do
      btc = insert(:project, %{name: "Bitcoin", slug: "bitcoin"})

      Sanbase.Project.SourceSlugMapping.create(%{
        source: "hyperliquid",
        slug: "BTC",
        project_id: btc.id
      })

      state =
        build_state(
          prev_unconfirmed: MapSet.new(["BTC"]),
          connected_at: System.monotonic_time(:millisecond) - 300_000
        )

      {:ok, new_state} = WebsocketScraper.handle_info(:reconcile_subscriptions, state)

      assert new_state.quarantine.probation == ["BTC"]
      assert :queue.is_empty(new_state.pending_sub_queue)
    end

    test "reconcile does not subscribe probation coins but keeps the probing coin subscribed" do
      btc = insert(:project, %{name: "Bitcoin", slug: "bitcoin"})

      Sanbase.Project.SourceSlugMapping.create(%{
        source: "hyperliquid",
        slug: "BTC",
        project_id: btc.id
      })

      # On probation, not subscribed -> reconcile must not queue it.
      state = build_state(probation: ["BTC"])
      {:ok, new_state} = WebsocketScraper.handle_info(:reconcile_subscriptions, state)
      assert :queue.is_empty(new_state.pending_sub_queue)

      # Mid-probe and confirmed -> reconcile must not unsubscribe it.
      state =
        build_state(
          probation: ["BTC"],
          probing: [%{coin: "BTC", started_ms: System.monotonic_time(:millisecond)}],
          active_subs: MapSet.new(["BTC"])
        )

      {:ok, new_state} = WebsocketScraper.handle_info(:reconcile_subscriptions, state)
      assert :queue.is_empty(new_state.pending_sub_queue)
    end

    test "reconcile defers new bulk subscribes while a probe is in flight" do
      eth = insert(:project, %{name: "Ethereum", slug: "ethereum"})

      Sanbase.Project.SourceSlugMapping.create(%{
        source: "hyperliquid",
        slug: "ETH",
        project_id: eth.id
      })

      state =
        build_state(
          probation: ["X"],
          probing: [%{coin: "X", started_ms: System.monotonic_time(:millisecond)}]
        )

      {:ok, new_state} = WebsocketScraper.handle_info(:reconcile_subscriptions, state)

      # ETH's subscribe waits for the probe verdict; nothing marked pending.
      assert :queue.is_empty(new_state.pending_sub_queue)
      assert new_state.prev_unconfirmed == MapSet.new()
    end

    test "reconcile does not subscribe quarantined coins and unsubscribes active ones" do
      btc = insert(:project, %{name: "Bitcoin", slug: "bitcoin"})

      Sanbase.Project.SourceSlugMapping.create(%{
        source: "hyperliquid",
        slug: "BTC",
        project_id: btc.id
      })

      state =
        build_state(
          active_subs: MapSet.new(["BTC"]),
          quarantined: %{"BTC" => "test reason"}
        )

      {:ok, new_state} = WebsocketScraper.handle_info(:reconcile_subscriptions, state)

      assert :queue.to_list(new_state.pending_sub_queue) == [{"unsubscribe", "BTC"}]
    end

    test "reconcile never subscribes coins ignored via HYPERLIQUID_IGNORED_COINS" do
      original = Application.get_env(:sanbase, Quarantine)
      Application.put_env(:sanbase, Quarantine, ignored_coins: "ANSEM, OTHER")

      on_exit(fn ->
        if is_nil(original),
          do: Application.delete_env(:sanbase, Quarantine),
          else: Application.put_env(:sanbase, Quarantine, original)
      end)

      ansem = insert(:project, %{name: "Ansem", slug: "sol-the-black-bull"})

      Sanbase.Project.SourceSlugMapping.create(%{
        source: "hyperliquid",
        slug: "ANSEM",
        project_id: ansem.id
      })

      state = build_state()
      {:ok, new_state} = WebsocketScraper.handle_info(:reconcile_subscriptions, state)

      assert :queue.is_empty(new_state.pending_sub_queue)
    end
  end

  describe "audit flow" do
    @describetag capture_log: true

    test "audit_result replaces audit_excluded and prunes probation" do
      ref = make_ref()

      state =
        build_state(probation: ["BAD", "Y"], audit_excluded: %{"OLD" => "gone"}, audit_ref: ref)

      result = %{
        desired: 3,
        universe: 100,
        unsupported: ["BAD"],
        reasons: %{"BAD" => "only a spot token on HL (no perp market)"}
      }

      {:ok, new_state} = WebsocketScraper.handle_info({:audit_result, ref, result}, state)

      # Replaced, not merged — "OLD" recovered; "BAD" left probation too.
      assert new_state.quarantine.audit_excluded == %{
               "BAD" => "only a spot token on HL (no perp market)"
             }

      assert new_state.quarantine.probation == ["Y"]
    end

    test "audit exclusion triggers an immediate reconcile and drops the queued subscribe" do
      ref = make_ref()

      state =
        build_state(
          pending_sub_queue: :queue.in({"subscribe", "BTC"}, :queue.new()),
          audit_ref: ref
        )

      result = %{desired: 1, universe: 10, unsupported: ["BTC"], reasons: %{"BTC" => "r"}}
      {:ok, state} = WebsocketScraper.handle_info({:audit_result, ref, result}, state)

      # New exclusions don't wait for the 60s reconcile tick.
      assert_receive :reconcile_subscriptions

      # The already-queued frame is dropped at send time ({:ok, _}, no reply)
      # and never recorded as sent.
      assert {:ok, new_state} = WebsocketScraper.handle_info(:flush_subs, state)
      assert :queue.is_empty(new_state.pending_sub_queue)
      assert new_state.quarantine.recent_sends == []
    end

    test "audit recovery (empty reasons) also triggers an immediate reconcile" do
      ref = make_ref()
      state = build_state(audit_excluded: %{"BTC" => "r"}, audit_ref: ref)

      result = %{desired: 1, universe: 10, unsupported: [], reasons: %{}}
      {:ok, new_state} = WebsocketScraper.handle_info({:audit_result, ref, result}, state)

      assert_receive :reconcile_subscriptions
      assert new_state.quarantine.audit_excluded == %{}
    end

    test "unchanged audit exclusion set does not trigger reconcile" do
      ref = make_ref()
      state = build_state(audit_excluded: %{"BTC" => "r"}, audit_ref: ref)

      result = %{desired: 1, universe: 10, unsupported: ["BTC"], reasons: %{"BTC" => "r"}}
      {:ok, _} = WebsocketScraper.handle_info({:audit_result, ref, result}, state)

      refute_receive :reconcile_subscriptions, 50
    end

    test "a stale audit result (superseded by a newer audit) is ignored" do
      state = build_state(audit_excluded: %{"KEEP" => "r"}, audit_ref: make_ref())

      stale_result = %{desired: 1, universe: 10, unsupported: [], reasons: %{}}

      {:ok, new_state} =
        WebsocketScraper.handle_info({:audit_result, make_ref(), stale_result}, state)

      assert new_state.quarantine.audit_excluded == %{"KEEP" => "r"}
      refute_receive :reconcile_subscriptions, 50
    end

    test "probation drops a queued bulk subscribe but lets the probe frame through" do
      # Bulk-queued subscribe for a coin that got probated meanwhile: dropped.
      state =
        build_state(
          pending_sub_queue: :queue.in({"subscribe", "X"}, :queue.new()),
          probation: ["X"]
        )

      assert {:ok, new_state} = WebsocketScraper.handle_info(:flush_subs, state)
      assert new_state.quarantine.recent_sends == []

      # The probe's own frame (coin marked in-flight) is sent normally.
      state =
        build_state(
          pending_sub_queue: :queue.in({"subscribe", "X"}, :queue.new()),
          probation: ["X"],
          probing: [%{coin: "X", started_ms: System.monotonic_time(:millisecond)}]
        )

      assert {:reply, {:text, _}, new_state} = WebsocketScraper.handle_info(:flush_subs, state)
      assert [%{coin: "X"}] = new_state.quarantine.recent_sends
    end

    test "failed audit keeps the previous verdicts" do
      ref = make_ref()
      state = build_state(audit_excluded: %{"BAD" => "reason"}, audit_ref: ref)

      {:ok, new_state} =
        WebsocketScraper.handle_info({:audit_result, ref, {:error, :nxdomain}}, state)

      assert new_state.quarantine.audit_excluded == %{"BAD" => "reason"}
    end

    test "reconcile respects audit exclusions: no subscribe, unsubscribes active" do
      btc = insert(:project, %{name: "Bitcoin", slug: "bitcoin"})

      Sanbase.Project.SourceSlugMapping.create(%{
        source: "hyperliquid",
        slug: "BTC",
        project_id: btc.id
      })

      state = build_state(active_subs: MapSet.new(["BTC"]), audit_excluded: %{"BTC" => "r"})
      {:ok, new_state} = WebsocketScraper.handle_info(:reconcile_subscriptions, state)

      assert :queue.to_list(new_state.pending_sub_queue) == [{"unsubscribe", "BTC"}]
    end

    test "connect does not start an audit again within the minimum gap" do
      recent = System.system_time(:millisecond) - 1_000

      {:ok, new_state} =
        WebsocketScraper.handle_connect(:fake_conn, build_state(last_audit_at: recent))

      assert new_state.last_audit_at == recent
      refute_receive {:audit_result, _, _}, 100
    end

    test "connect starts an audit when the gap has passed" do
      with_mock Sanbase.Hyperliquid.Bbo.CoinUniverse,
        audit: fn -> %{desired: 0, universe: 1, unsupported: [], reasons: %{}} end do
        stale = System.system_time(:millisecond) - 60_000

        {:ok, new_state} =
          WebsocketScraper.handle_connect(:fake_conn, build_state(last_audit_at: stale))

        assert new_state.last_audit_at > stale
        assert_receive {:audit_result, _ref, %{reasons: %{}}}, 1_000
      end
    end

    test "reconcile no longer triggers audits" do
      state = build_state()
      {:ok, new_state} = WebsocketScraper.handle_info(:reconcile_subscriptions, state)

      assert Map.get(new_state, :last_audit_at, 0) == 0
      refute_receive {:audit_result, _, _}, 100
    end
  end

  describe "handle_connect" do
    test "refreshes state, schedules main timers, signals reconcile" do
      state =
        build_state(
          reconnect_backoff_ms: 16_000,
          last_message_time: 0,
          timers: %{},
          # Fresh audit — keeps handle_connect from spawning a real audit
          # task (HTTP + DB) inside the test.
          last_audit_at: System.system_time(:millisecond)
        )

      {:ok, new_state} = WebsocketScraper.handle_connect(:fake_conn, state)

      # Backoff must survive connect — it only resets after a connection
      # proves stable (see handle_disconnect), else a flapping remote keeps
      # the reconnect loop at full speed forever.
      assert new_state.reconnect_backoff_ms == 16_000
      assert new_state.last_message_time > 0
      assert [_connected_now] = new_state.connect_times

      for key <- [
            :ping,
            :healthcheck,
            :flush_coalesced,
            :reconcile_subscriptions,
            :probe_next,
            :audit
          ] do
        assert Map.has_key?(new_state.timers, key), "missing #{key} timer"
      end

      refute Map.has_key?(new_state.timers, :flush_subs)
      assert_receive :reconcile_subscriptions
    end
  end

  describe "enabled?/0" do
    setup do
      original = Application.get_env(:sanbase, WebsocketScraper)

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:sanbase, WebsocketScraper)
        else
          Application.put_env(:sanbase, WebsocketScraper, original)
        end
      end)

      :ok
    end

    for v <- ["true", "TRUE", "True", " true ", "1"] do
      test "treats #{inspect(v)} as enabled" do
        put_enabled(unquote(v))
        assert WebsocketScraper.enabled?()
      end
    end

    for v <- ["false", "FALSE", "0", "", "no"] do
      test "treats #{inspect(v)} as disabled" do
        put_enabled(unquote(v))
        refute WebsocketScraper.enabled?()
      end
    end
  end
end
