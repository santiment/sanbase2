defmodule Sanbase.Hyperliquid.Bbo.WebsocketScraperTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Hyperliquid.Bbo.WebsocketScraper

  @topic "hyperliquid_bbo_prices"
  @exporter :hyperliquid_bbo_exporter

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
      timers: %{}
    }
    |> Map.merge(Map.new(overrides))
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

      queued =
        state.pending_sub_queue
        |> :queue.to_list()
        |> Enum.map(fn {:text, json} -> Jason.decode!(json) end)

      methods_by_coin =
        Enum.into(queued, %{}, fn %{"method" => m, "subscription" => %{"coin" => c}} -> {c, m} end)

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
    test "drains one queued frame per tick via reply" do
      frame = {:text, Jason.encode!(%{"foo" => 1})}
      queue = :queue.in(frame, :queue.new())
      state = build_state(pending_sub_queue: queue)

      assert {:reply, ^frame, new_state} =
               WebsocketScraper.handle_info(:flush_subs, state)

      assert :queue.is_empty(new_state.pending_sub_queue)
    end

    test "no-op when queue is empty" do
      state = build_state()
      assert {:ok, _new_state} = WebsocketScraper.handle_info(:flush_subs, state)
    end
  end

  describe "flush_subs scheduling" do
    test "draining last frame stops the timer (no re-arm)" do
      frame = {:text, "x"}
      queue = :queue.in(frame, :queue.new())
      state = build_state(pending_sub_queue: queue, timers: %{flush_subs: make_ref()})

      assert {:reply, ^frame, new_state} =
               WebsocketScraper.handle_info(:flush_subs, state)

      refute Map.has_key?(new_state.timers, :flush_subs)
      assert :queue.is_empty(new_state.pending_sub_queue)
    end

    test "draining when more remain re-arms the timer" do
      frame_a = {:text, "a"}
      frame_b = {:text, "b"}
      queue = :queue.from_list([frame_a, frame_b])
      state = build_state(pending_sub_queue: queue, timers: %{flush_subs: make_ref()})

      assert {:reply, ^frame_a, new_state} =
               WebsocketScraper.handle_info(:flush_subs, state)

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

    test "clears in-flight state, resets healthcheck failures, doubles backoff" do
      state =
        build_state(
          active_subs: MapSet.new(["BTC", "ETH"]),
          pending_sub_queue: :queue.in({:text, "x"}, :queue.new()),
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

    test "short-lived connection keeps doubling the backoff and clears connected_at" do
      state =
        build_state(
          connected_at: System.monotonic_time(:millisecond) - 3_000,
          reconnect_backoff_ms: 4
        )

      {:reconnect, new_state} =
        WebsocketScraper.handle_disconnect(%{reason: {:remote, :closed}}, state)

      assert new_state.reconnect_backoff_ms == 8
      assert new_state.connected_at == nil
    end
  end

  # The stable-reset paths are tested through backoff_plan/3 because
  # handle_disconnect/2 sleeps its result for real — the reset branch would
  # block the suite for @reconnect_initial_ms (1s) plus jitter per test.
  describe "backoff_plan/3" do
    test "connection that lived past the stable threshold restarts the ladder" do
      assert {1_000, 2_000} = WebsocketScraper.backoff_plan(16_000, 120_000, 1)
    end

    test "short lifetime keeps climbing the ladder" do
      assert {4_000, 8_000} = WebsocketScraper.backoff_plan(4_000, 3_000, 1)
    end

    test "failed reconnect attempt (attempt_number > 1) never restarts the ladder" do
      assert {4_000, 8_000} = WebsocketScraper.backoff_plan(4_000, 120_000, 2)
    end

    test "nil lifetime (no live connection was dropped) keeps climbing" do
      assert {4_000, 8_000} = WebsocketScraper.backoff_plan(4_000, nil, 1)
    end

    test "sleep base plus max jitter never exceeds the 20s ceiling" do
      {base, next} = WebsocketScraper.backoff_plan(1_000_000, 3_000, 1)
      assert base + 1_000 <= 20_000
      assert next + 1_000 <= 20_000
    end
  end

  describe "handle_connect" do
    test "refreshes state, schedules main timers, signals reconcile" do
      state =
        build_state(
          reconnect_backoff_ms: 16_000,
          last_message_time: 0,
          timers: %{}
        )

      {:ok, new_state} = WebsocketScraper.handle_connect(:fake_conn, state)

      # Backoff must survive connect — it only resets after a connection
      # proves stable (see handle_disconnect), else a flapping remote keeps
      # the reconnect loop at full speed forever.
      assert new_state.reconnect_backoff_ms == 16_000
      assert new_state.last_message_time > 0
      assert [_connected_now] = new_state.connect_times

      for key <- [:ping, :healthcheck, :flush_coalesced, :reconcile_subscriptions] do
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
