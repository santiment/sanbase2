defmodule Sanbase.Metric.TagEventTest do
  use Sanbase.DataCase, async: false

  import ExUnit.CaptureLog

  alias Sanbase.Metric.Tag
  alias Sanbase.EventBus.MetricRegistrySubscriber

  @receiver :tag_event_test_receiver

  defmodule Forwarder do
    @moduledoc """
    Test subscriber that forwards every event on the subscribed topics to the
    test process, so tests can assert on the emitted event payloads.
    """

    def process({_topic, _id} = event_shadow) do
      event = EventBus.fetch_event(event_shadow)

      case Process.whereis(:tag_event_test_receiver) do
        nil -> :ok
        pid -> send(pid, {:tag_event, event.data})
      end

      EventBus.mark_as_completed({__MODULE__, event_shadow})
      :ok
    end
  end

  setup_all do
    # In test env MetricRegistrySubscriber is in the disabled_subscribers list,
    # so it must be subscribed explicitly to test the topic -> subscriber ->
    # handler dispatch. Same pattern as KafkaExporterSubscriberTest.
    EventBus.subscribe({Forwarder, ["metric_tag_events"]})
    Sanbase.EventBus.subscribe_subscriber(MetricRegistrySubscriber)
    # EventBus.subscribe/1 is a cast; give it time to be established
    Process.sleep(200)

    on_exit(fn ->
      Sanbase.EventBus.drain_topics(["metric_tag_events"], 10_000)
      EventBus.unsubscribe(Forwarder)
      Sanbase.EventBus.unsubscribe_subscriber(MetricRegistrySubscriber)
    end)

    :ok
  end

  setup do
    Process.register(self(), @receiver)
    :ok
  end

  describe "wiring" do
    test "the metric_tag_events topic is registered at boot" do
      assert :metric_tag_events in EventBus.topics()
    end

    test "MetricRegistrySubscriber subscribes to the metric_tag_events topic" do
      assert "metric_tag_events" in MetricRegistrySubscriber.topics()
    end

    test "the tag event emitter emits on the metric_tag_events topic" do
      assert Sanbase.Metric.Tag.EventEmitter.topic() == :metric_tag_events
    end

    test "metric_tag_change is a valid event type" do
      assert Sanbase.EventBus.EventValidation.valid?(%{event_type: :metric_tag_change})
    end
  end

  describe "event emission" do
    test "every tag and mapping mutation emits a metric_tag_change event" do
      {:ok, tag} = Tag.create_tag(%{name: "emit_test_tag"})
      assert_receive {:tag_event, %{event_type: :metric_tag_change}}, 1000

      {:ok, tag} = Tag.update_tag(tag, %{description: "updated"})
      assert_receive {:tag_event, %{event_type: :metric_tag_change}}, 1000

      {:ok, mapping} = Tag.create_mapping(%{tag_id: tag.id, module: "M", metric: "emit_metric"})
      assert_receive {:tag_event, %{event_type: :metric_tag_change}}, 1000

      {:ok, _} = Tag.delete_mapping(mapping)
      assert_receive {:tag_event, %{event_type: :metric_tag_change}}, 1000

      {:ok, _} = Tag.delete_tag(tag)
      assert_receive {:tag_event, %{event_type: :metric_tag_change}}, 1000

      refute_receive {:tag_event, _}, 100
    end

    test "failed mutations do not emit events" do
      {:ok, _} = Tag.create_tag(%{name: "emit_dup_tag"})
      assert_receive {:tag_event, %{event_type: :metric_tag_change}}, 1000

      assert {:error, _} = Tag.create_tag(%{name: "emit_dup_tag"})
      refute_receive {:tag_event, _}, 100
    end
  end

  describe "event processing" do
    test "the subscriber dispatches metric_tag_change to the configured handler" do
      # In test env the configured handler is on_metric_tag_change_test_env/0,
      # which logs instead of refreshing caches (to avoid Ecto sandbox
      # ownership errors in the subscriber process).
      log =
        capture_log(fn ->
          {:ok, _} = Tag.create_tag(%{name: "process_test_tag"})
          # The emitter's maybe_wait/2 returns only after all subscribers have
          # marked the event as completed, so the handler has already run here.
          Logger.flush()
        end)

      assert log =~ "Metric Tag Change event received"
    end

    test "on_metric_tag_change/0 (the prod handler) refreshes the tag caches" do
      {:ok, tag} = Tag.create_tag(%{name: "prod_handler_tag"})

      # Pin a snapshot computed before the mapping exists. Without this the
      # lazy cache-miss refresh would make the assertions below pass even if
      # the handler refreshed nothing.
      true = Tag.refresh_stored_terms()

      {:ok, _} = Tag.create_mapping(%{tag_id: tag.id, module: "M", metric: "prod_handler_metric"})
      assert Tag.tags_for_metric("prod_handler_metric") == []

      assert :ok = MetricRegistrySubscriber.on_metric_tag_change()

      assert Tag.tags_for_metric("prod_handler_metric") == ["prod_handler_tag"]
      assert MapSet.member?(Tag.metrics_for_tag("prod_handler_tag"), "prod_handler_metric")
    end
  end
end
