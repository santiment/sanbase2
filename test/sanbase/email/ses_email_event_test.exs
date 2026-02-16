defmodule Sanbase.Email.SesEmailEventTest do
  use Sanbase.DataCase

  alias Sanbase.Email.SesEmailEvent

  @valid_attrs %{
    message_id: "ses-msg-001",
    email: "user@example.com",
    event_type: "Delivery",
    timestamp: ~U[2026-02-16 10:00:00Z]
  }

  describe "changeset/2" do
    test "valid with required fields" do
      changeset = SesEmailEvent.changeset(%SesEmailEvent{}, @valid_attrs)
      assert changeset.valid?
    end

    test "valid with all fields" do
      attrs =
        Map.merge(@valid_attrs, %{
          event_type: "Bounce",
          bounce_type: "Permanent",
          bounce_sub_type: "General",
          raw_data: %{"bounce" => %{"bounceType" => "Permanent"}}
        })

      changeset = SesEmailEvent.changeset(%SesEmailEvent{}, attrs)
      assert changeset.valid?
    end

    test "invalid without required fields" do
      changeset = SesEmailEvent.changeset(%SesEmailEvent{}, %{})
      refute changeset.valid?

      errors = errors_on(changeset)
      assert "can't be blank" in errors.message_id
      assert "can't be blank" in errors.email
      assert "can't be blank" in errors.event_type
      assert "can't be blank" in errors.timestamp
    end

    test "invalid with unknown event type" do
      attrs = Map.put(@valid_attrs, :event_type, "Unknown")
      changeset = SesEmailEvent.changeset(%SesEmailEvent{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).event_type
    end

    test "accepts all valid event types" do
      for event_type <- SesEmailEvent.event_types() do
        attrs = Map.put(@valid_attrs, :event_type, event_type)
        changeset = SesEmailEvent.changeset(%SesEmailEvent{}, attrs)
        assert changeset.valid?, "Expected #{event_type} to be valid"
      end
    end
  end

  describe "create/1" do
    test "inserts a valid event" do
      assert {:ok, event} = SesEmailEvent.create(@valid_attrs)
      assert event.id
      assert event.message_id == "ses-msg-001"
      assert event.email == "user@example.com"
      assert event.event_type == "Delivery"
    end

    test "returns error for invalid attrs" do
      assert {:error, changeset} = SesEmailEvent.create(%{})
      refute changeset.valid?
    end

    test "ignores duplicate (message_id, email, event_type) on SNS retry" do
      assert {:ok, first} = SesEmailEvent.create(@valid_attrs)
      assert first.id

      assert {:ok, duplicate} = SesEmailEvent.create(@valid_attrs)
      assert is_nil(duplicate.id)

      assert SesEmailEvent.count_events() == 1
    end
  end

  describe "list_events/1" do
    setup do
      {:ok, _} =
        SesEmailEvent.create(%{
          message_id: "msg-1",
          email: "alice@example.com",
          event_type: "Send",
          timestamp: ~U[2026-02-16 09:00:00Z]
        })

      {:ok, _} =
        SesEmailEvent.create(%{
          message_id: "msg-2",
          email: "alice@example.com",
          event_type: "Delivery",
          timestamp: ~U[2026-02-16 09:01:00Z]
        })

      {:ok, _} =
        SesEmailEvent.create(%{
          message_id: "msg-3",
          email: "bob@example.com",
          event_type: "Bounce",
          bounce_type: "Permanent",
          bounce_sub_type: "General",
          timestamp: ~U[2026-02-16 09:02:00Z]
        })

      :ok
    end

    test "returns all events ordered by timestamp desc" do
      events = SesEmailEvent.list_events()
      assert length(events) == 3
      assert hd(events).event_type == "Bounce"
    end

    test "filters by event type" do
      events = SesEmailEvent.list_events(event_type: "Bounce")
      assert length(events) == 1
      assert hd(events).email == "bob@example.com"
    end

    test "filters by email search" do
      events = SesEmailEvent.list_events(email_search: "alice")
      assert length(events) == 2
    end

    test "paginates results" do
      events = SesEmailEvent.list_events(page: 1, page_size: 2)
      assert length(events) == 2

      events = SesEmailEvent.list_events(page: 2, page_size: 2)
      assert length(events) == 1
    end

    test "combines filters" do
      events = SesEmailEvent.list_events(event_type: "Delivery", email_search: "alice")
      assert length(events) == 1
      assert hd(events).event_type == "Delivery"
    end
  end

  describe "count_events/1" do
    setup do
      for i <- 1..5 do
        SesEmailEvent.create(%{
          message_id: "msg-#{i}",
          email: "user#{i}@example.com",
          event_type: if(rem(i, 2) == 0, do: "Bounce", else: "Delivery"),
          timestamp: ~U[2026-02-16 10:00:00Z]
        })
      end

      :ok
    end

    test "counts all events" do
      assert SesEmailEvent.count_events() == 5
    end

    test "counts with filters" do
      assert SesEmailEvent.count_events(event_type: "Bounce") == 2
      assert SesEmailEvent.count_events(event_type: "Delivery") == 3
    end
  end

  describe "stats_since/1" do
    test "returns counts grouped by event type" do
      for {type, count} <- [{"Send", 3}, {"Delivery", 2}, {"Bounce", 1}] do
        Enum.each(1..count, fn i ->
          {:ok, _} =
            SesEmailEvent.create(%{
              message_id: "msg-#{type}-#{i}",
              email: "user@example.com",
              event_type: type,
              timestamp: ~U[2026-02-16 10:00:00Z]
            })
        end)
      end

      stats = SesEmailEvent.stats_since(~U[2026-02-15 00:00:00Z])
      assert stats["Send"] == 3
      assert stats["Delivery"] == 2
      assert stats["Bounce"] == 1
    end

    test "returns empty map when no events" do
      assert SesEmailEvent.stats_since(~U[2026-02-15 00:00:00Z]) == %{}
    end
  end
end
