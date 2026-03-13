defmodule SanbaseWeb.Graphql.EntityPublicTriggerTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    trigger_owner = insert(:user)
    other_user = insert(:user)
    conn = setup_jwt_auth(build_conn(), other_user)

    webhook_settings = %{
      "type" => "metric_signal",
      "metric" => "daily_active_addresses",
      "target" => %{"slug" => "santiment"},
      "channel" => [%{"webhook" => "https://example.com/secret_hook"}],
      "time_window" => "1d",
      "operation" => %{"percent_up" => 300.0},
      "template" => "Price of {{slug}} changed by {{percent_change}}%",
      "extra_explanation" => "some private note"
    }

    user_trigger =
      insert(:user_trigger,
        user: trigger_owner,
        is_public: true,
        trigger: %{title: "Webhook alert", is_public: true, settings: webhook_settings}
      )

    %{conn: conn, trigger_owner: trigger_owner, user_trigger: user_trigger}
  end

  describe "getMostRecent" do
    test "triggers have public shape with no private settings", context do
      %{conn: conn, user_trigger: user_trigger} = context

      result = get_most_recent(conn, :user_trigger)
      [entity] = result["data"]
      trigger = entity["userTrigger"]["trigger"]

      assert_public_trigger_shape(trigger, user_trigger)
    end
  end

  describe "getMostVoted" do
    test "triggers have public shape with no private settings", context do
      %{conn: conn, user_trigger: user_trigger} = context

      vote(conn, user_trigger.id)

      result = get_most_voted(conn, :user_trigger)
      [entity] = result["data"]
      trigger = entity["userTrigger"]["trigger"]

      assert_public_trigger_shape(trigger, user_trigger)
    end
  end

  describe "public_user_trigger does not leak private user data" do
    test "allPublicTriggers user field exposes only public user data and sanitized triggers",
         context do
      %{conn: conn, trigger_owner: trigger_owner} = context

      # Also insert a private trigger that should not appear via user.triggers
      insert(:user_trigger,
        user: trigger_owner,
        is_public: false,
        trigger: %{
          title: "Secret private alert",
          is_public: false,
          settings: %{
            "type" => "metric_signal",
            "metric" => "daily_active_addresses",
            "target" => %{"slug" => "santiment"},
            "channel" => "telegram",
            "time_window" => "1d",
            "operation" => %{"percent_up" => 100.0}
          }
        }
      )

      result = all_public_triggers_with_user(conn)
      assert length(result) == 1

      public_user_trigger = hd(result)
      user_data = public_user_trigger["user"]

      # Public user fields are present
      assert user_data["id"] == "#{trigger_owner.id}"
      assert user_data["username"] == trigger_owner.username

      # Email is hidden by default
      assert user_data["email"] == "<email hidden>"

      # Nested triggers on the user are only public ones with sanitized settings
      user_triggers = user_data["triggers"]
      assert length(user_triggers) == 1

      nested_settings = hd(user_triggers)["settings"]
      refute Map.has_key?(nested_settings, "channel")
      refute Map.has_key?(nested_settings, "template")
      refute Map.has_key?(nested_settings, "extra_explanation")
    end

    test "getMostRecent user field on public_user_trigger exposes only public data", context do
      %{conn: conn, trigger_owner: trigger_owner} = context

      result = get_most_recent_with_user(conn)
      [entity] = result["data"]
      user_data = entity["userTrigger"]["user"]

      assert user_data["id"] == "#{trigger_owner.id}"
      assert user_data["username"] == trigger_owner.username
      assert user_data["email"] == "<email hidden>"

      # Nested triggers have sanitized settings
      user_triggers = user_data["triggers"]
      assert length(user_triggers) == 1
      nested_settings = hd(user_triggers)["settings"]
      refute Map.has_key?(nested_settings, "channel")
      refute Map.has_key?(nested_settings, "template")
    end
  end

  defp all_public_triggers_with_user(conn) do
    query = """
    {
      allPublicTriggers {
        user_id
        user {
          id
          email
          username
          triggers {
            id
            title
            settings
          }
        }
        trigger {
          id
          title
          settings
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "allPublicTriggers"))
    |> json_response(200)
    |> get_in(["data", "allPublicTriggers"])
  end

  defp get_most_recent_with_user(conn) do
    query = """
    {
      getMostRecent(types: [USER_TRIGGER], page: 1, pageSize: 10, minTitleLength: 0, minDescriptionLength: 0){
        stats { currentPage currentPageSize totalPagesCount totalEntitiesCount }
        data {
          userTrigger{
            user {
              id
              email
              username
              triggers {
                id
                title
                settings
              }
            }
            trigger{
              id
              title
              settings
            }
          }
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "getMostRecent"])
  end

  defp assert_public_trigger_shape(trigger, user_trigger) do
    # Trigger-level public fields are present with correct values
    assert trigger["id"] == user_trigger.id
    assert trigger["title"] == "Webhook alert"
    assert is_binary(trigger["insertedAt"])
    assert is_binary(trigger["updatedAt"])
    assert trigger["isPublic"] == true
    assert Map.has_key?(trigger, "isFeatured")
    assert Map.has_key?(trigger, "description")
    assert Map.has_key?(trigger, "iconUrl")

    # Trigger-level fields that are now public
    assert Map.has_key?(trigger, "isActive")
    assert Map.has_key?(trigger, "isRepeating")
    assert Map.has_key?(trigger, "isFrozen")

    # Trigger-level private fields are NOT queryable (not in schema)
    refute Map.has_key?(trigger, "cooldown")
    refute Map.has_key?(trigger, "isHidden")
    # Settings public fields are present
    settings = trigger["settings"]
    assert settings["type"] == "metric_signal"
    assert settings["metric"] == "daily_active_addresses"
    assert settings["target"] == %{"slug" => "santiment"}
    assert Map.has_key?(settings, "operation")
    assert Map.has_key?(settings, "time_window")

    # Settings private fields are stripped
    refute Map.has_key?(settings, "channel")
    refute Map.has_key?(settings, "template")
    refute Map.has_key?(settings, "extra_explanation")
  end

  defp vote(conn, user_trigger_id) do
    mutation = """
    mutation {
      vote(userTriggerId: #{user_trigger_id}) {
        votes{ totalVotes }
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  defp get_most_recent(conn, entity_or_entities) do
    types = List.wrap(entity_or_entities)

    query = """
    {
      getMostRecent(types: [#{Enum.map_join(types, ", ", &entity_type_to_gql/1)}], page: 1, pageSize: 10, minTitleLength: 0, minDescriptionLength: 0){
        stats { currentPage currentPageSize totalPagesCount totalEntitiesCount }
        data {
          userTrigger{
            trigger{
              id
              title
              description
              iconUrl
              settings
              isPublic
              isActive
              isRepeating
              isFrozen
              isFeatured
              insertedAt
              updatedAt
            }
          }
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "getMostRecent"])
  end

  defp get_most_voted(conn, entity_or_entities) do
    types = List.wrap(entity_or_entities)

    query = """
    {
      getMostVoted(types: [#{Enum.map_join(types, ", ", &entity_type_to_gql/1)}], page: 1, pageSize: 10, cursor: {type: AFTER, datetime: "utc_now-30d"}){
        stats { currentPage currentPageSize totalPagesCount totalEntitiesCount }
        data {
          userTrigger{
            trigger{
              id
              title
              description
              iconUrl
              settings
              isPublic
              isActive
              isRepeating
              isFrozen
              isFeatured
              insertedAt
              updatedAt
            }
          }
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "getMostVoted"])
  end

  defp entity_type_to_gql(:user_trigger), do: "USER_TRIGGER"
end
