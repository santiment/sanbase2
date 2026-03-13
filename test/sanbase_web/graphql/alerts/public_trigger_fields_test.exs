defmodule SanbaseWeb.Graphql.PublicTriggerFieldsTest do
  use SanbaseWeb.ConnCase, async: true

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    %{user: user, conn: conn}
  end

  describe "currentUser triggers expose private fields" do
    test "settings include channel and all trigger fields are present", context do
      %{conn: conn, user: user} = context

      insert(:user_trigger, user: user, is_public: false)

      result = current_user_triggers(conn)
      trigger = hd(result)

      # Private trigger-level fields are present
      assert Map.has_key?(trigger, "cooldown")
      assert Map.has_key?(trigger, "isActive")
      assert Map.has_key?(trigger, "isRepeating")
      assert Map.has_key?(trigger, "isFrozen")
      assert Map.has_key?(trigger, "isHidden")

      # Settings contain private fields like channel
      assert Map.has_key?(trigger["settings"], "channel")
    end
  end

  describe "getUser triggers expose only public fields" do
    test "only public triggers are returned", context do
      %{conn: conn, user: user} = context

      insert(:user_trigger, user: user, is_public: false)
      public_trigger = insert(:user_trigger, user: user, is_public: true)

      result = public_user_triggers(conn, user)

      assert length(result) == 1
      assert hd(result)["id"] == public_trigger.id
    end

    test "private trigger-level fields are not exposed", context do
      %{conn: conn, user: user} = context

      insert(:user_trigger, user: user, is_public: true)

      result = public_user_triggers(conn, user)
      trigger = hd(result)

      # Public fields are present
      assert Map.has_key?(trigger, "id")
      assert Map.has_key?(trigger, "title")
      assert Map.has_key?(trigger, "description")
      assert Map.has_key?(trigger, "settings")
      assert Map.has_key?(trigger, "isPublic")
      assert Map.has_key?(trigger, "insertedAt")
      assert Map.has_key?(trigger, "updatedAt")

      # Private trigger-level fields are NOT present
      refute Map.has_key?(trigger, "cooldown")
      refute Map.has_key?(trigger, "isActive")
      refute Map.has_key?(trigger, "isRepeating")
      refute Map.has_key?(trigger, "isFrozen")
      refute Map.has_key?(trigger, "isHidden")
    end

    test "settings have private fields stripped", context do
      %{conn: conn, user: user} = context

      insert(:user_trigger, user: user, is_public: true)

      result = public_user_triggers(conn, user)
      settings = hd(result)["settings"]

      # Public settings fields are present
      assert Map.has_key?(settings, "type")
      assert Map.has_key?(settings, "metric")
      assert Map.has_key?(settings, "target")
      assert Map.has_key?(settings, "operation")

      # Private settings fields are NOT present
      refute Map.has_key?(settings, "channel")
      refute Map.has_key?(settings, "template")
      refute Map.has_key?(settings, "extra_explanation")
    end

    test "webhook channel is not exposed in public trigger settings", context do
      %{conn: conn, user: user} = context

      webhook_settings = %{
        "type" => "metric_signal",
        "metric" => "daily_active_addresses",
        "target" => %{"slug" => "santiment"},
        "channel" => [%{"webhook" => "https://example.com/secret_webhook"}],
        "time_window" => "1d",
        "operation" => %{"percent_up" => 300.0}
      }

      insert(:user_trigger,
        user: user,
        is_public: true,
        trigger: %{title: "Webhook trigger", is_public: true, settings: webhook_settings}
      )

      result = public_user_triggers(conn, user)
      settings = hd(result)["settings"]

      refute Map.has_key?(settings, "channel")
      assert settings["type"] == "metric_signal"
      assert settings["metric"] == "daily_active_addresses"
    end
  end

  describe "currentUser and getUser trigger shapes match for shared fields" do
    test "public trigger has same values as private trigger for kept fields", context do
      %{conn: conn, user: user} = context

      insert(:user_trigger,
        user: user,
        is_public: true,
        trigger: %{
          title: "Shape test",
          description: "Testing shape",
          is_public: true,
          settings: %{
            "type" => "metric_signal",
            "metric" => "daily_active_addresses",
            "target" => %{"slug" => "santiment"},
            "channel" => [%{"webhook" => "https://example.com/hook"}],
            "time_window" => "1d",
            "operation" => %{"percent_up" => 300.0}
          }
        }
      )

      [private_trigger] = current_user_all_fields(conn)
      [public_trigger] = public_user_all_fields(conn, user)

      # Non-settings shared fields have identical values
      for field <- ~w(id title description isPublic insertedAt updatedAt iconUrl) do
        assert Map.get(private_trigger, field) == Map.get(public_trigger, field),
               "Field #{field} differs: private=#{inspect(Map.get(private_trigger, field))}, public=#{inspect(Map.get(public_trigger, field))}"
      end

      # Public settings is a subset of private settings (minus private keys)
      private_settings = private_trigger["settings"]
      public_settings = public_trigger["settings"]

      for key <- Map.keys(public_settings) do
        assert Map.get(public_settings, key) == Map.get(private_settings, key),
               "Settings key #{key} differs"
      end

      # Private settings keys are not in public settings
      for key <- ~w(channel template extra_explanation) do
        refute Map.has_key?(public_settings, key),
               "Expected public settings NOT to have key #{key}"
      end

      # Private-only fields are present on currentUser trigger
      for field <- ~w(cooldown isActive isRepeating isFrozen isHidden lastTriggeredDatetime) do
        assert Map.has_key?(private_trigger, field),
               "Expected currentUser trigger to have field #{field}"
      end

      # Private-only fields are absent on getUser trigger
      for field <- ~w(cooldown isActive isRepeating isFrozen isHidden lastTriggeredDatetime) do
        refute Map.has_key?(public_trigger, field),
               "Expected getUser trigger NOT to have field #{field}"
      end
    end
  end

  defp current_user_all_fields(conn) do
    query = """
    {
      currentUser {
        triggers{
          id
          title
          description
          iconUrl
          settings
          cooldown
          isPublic
          isHidden
          isActive
          isRepeating
          isFrozen
          insertedAt
          updatedAt
          lastTriggeredDatetime
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "currentUser"))
    |> json_response(200)
    |> get_in(["data", "currentUser", "triggers"])
  end

  defp public_user_all_fields(conn, user) do
    query = """
    {
      getUser(selector: { id: #{user.id} }) {
        triggers{
          id
          title
          description
          iconUrl
          settings
          isPublic
          insertedAt
          updatedAt
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "getUser"))
    |> json_response(200)
    |> get_in(["data", "getUser", "triggers"])
  end

  defp current_user_triggers(conn) do
    query = """
    {
      currentUser {
        triggers{
          id
          title
          settings
          cooldown
          isActive
          isRepeating
          isFrozen
          isHidden
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "currentUser"))
    |> json_response(200)
    |> get_in(["data", "currentUser", "triggers"])
  end

  defp public_user_triggers(conn, user) do
    query = """
    {
      getUser(selector: { id: #{user.id} }) {
        triggers{
          id
          title
          description
          settings
          isPublic
          insertedAt
          updatedAt
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "getUser"))
    |> json_response(200)
    |> get_in(["data", "getUser", "triggers"])
  end
end
