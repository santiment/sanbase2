defmodule SanbaseWeb.Graphql.ChartConfigurationApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    project = insert(:random_project)
    project2 = insert(:random_project)
    user = insert(:user)
    user2 = insert(:user)

    conn_no_user = build_conn()
    conn = setup_jwt_auth(build_conn(), user)
    conn2 = setup_jwt_auth(build_conn(), user2)

    post = insert(:post, user: user, title: "Title")

    settings = %{
      title: "My config",
      description: "some description",
      is_public: false,
      anomalies: ["daily_active_addesses_anomaly"],
      post_id: post.id,
      metrics: [
        "price_usd",
        "daily_active_addresses",
        "ethereum-CC-ETH-CC-daily_active_addresses"
      ],
      metrics_json: %{
        "price_usd" => %{"slug" => "bitcoin"}
      },
      queries: %{
        "top_holders" => %{
          "query" => "top_holders",
          "args" => %{"from" => "utc_now-1d", "to" => "utc_now"},
          "selected_fields" => ["datetime", "trx_value"]
        }
      },
      drawings: %{
        "lines" => [
          %{"x0" => 0, "y0" => 0, "x1" => 15, "y1" => 15},
          %{"x0" => 20, "y0" => 0, "x1" => 55, "y1" => 15}
        ]
      },
      options: %{
        "multi_chart" => true,
        "log_scale" => true
      },
      project_id: project.id
    }

    %{
      conn: conn,
      conn2: conn2,
      conn_no_user: conn_no_user,
      user: user,
      user2: user2,
      post: post,
      project: project,
      project2: project2,
      settings: settings
    }
  end

  describe "chart configuration voting" do
    test "vote and downvote", context do
      %{conn: conn, settings: settings} = context

      config =
        create_chart_configuration(conn, settings)
        |> get_in(["data", "createChartConfiguration"])

      config_res = get_chart_configuration_votes(conn, config["id"])
      assert config_res["votedAt"] == nil

      assert config_res["votes"] == %{
               "currentUserVotes" => 0,
               "totalVoters" => 0,
               "totalVotes" => 0
             }

      %{"data" => %{"vote" => vote}} = vote(conn, config["id"], direction: :up)
      config_res = get_chart_configuration_votes(conn, config["id"])
      assert config_res["votedAt"] == vote["votedAt"]
      voted_at = vote["votedAt"] |> Sanbase.DateTimeUtils.from_iso8601!()
      assert Sanbase.TestUtils.datetime_close_to(voted_at, Timex.now(), seconds: 2)
      assert vote["votes"] == config_res["votes"]
      assert vote["votes"] == %{"currentUserVotes" => 1, "totalVoters" => 1, "totalVotes" => 1}

      %{"data" => %{"vote" => vote}} = vote(conn, config["id"], direction: :up)
      config_res = get_chart_configuration_votes(conn, config["id"])
      assert vote["votes"] == config_res["votes"]
      assert vote["votes"] == %{"currentUserVotes" => 2, "totalVoters" => 1, "totalVotes" => 2}

      %{"data" => %{"unvote" => vote}} = vote(conn, config["id"], direction: :down)
      config_res = get_chart_configuration_votes(conn, config["id"])
      assert vote["votes"] == config_res["votes"]
      assert vote["votes"] == %{"currentUserVotes" => 1, "totalVoters" => 1, "totalVotes" => 1}

      %{"data" => %{"unvote" => vote}} = vote(conn, config["id"], direction: :down)
      config_res = get_chart_configuration_votes(conn, config["id"])
      assert vote["votes"] == config_res["votes"]
      assert vote["votedAt"] == nil
      assert vote["votes"] == %{"currentUserVotes" => 0, "totalVoters" => 0, "totalVotes" => 0}
    end

    defp get_chart_configuration_votes(conn, chart_configuration_id) do
      query = """
      {
        chartConfiguration(id: #{chart_configuration_id}){
          id
          votedAt
          votes { currentUserVotes totalVotes totalVoters }
        }
      }
      """

      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)
      |> get_in(["data", "chartConfiguration"])
    end

    defp vote(conn, chart_configuration_id, opts) do
      function =
        case Keyword.get(opts, :direction, :up) do
          :up -> "vote"
          :down -> "unvote"
        end

      mutation = """
      mutation {
        #{function}(chartConfigurationId: #{chart_configuration_id}){
          votedAt
          votes { currentUserVotes totalVotes totalVoters }
        }
      }
      """

      conn
      |> post("/graphql", mutation_skeleton(mutation))
      |> json_response(200)
    end
  end

  describe "chart configuration mutations" do
    test "create", context do
      %{user: user, conn: conn, project: project, post: post, settings: settings} = context

      config =
        create_chart_configuration(conn, settings)
        |> get_in(["data", "createChartConfiguration"])

      assert config["title"] == settings.title
      assert config["description"] == settings.description
      assert config["isPublic"] == settings.is_public
      assert config["anomalies"] == settings.anomalies
      assert config["metrics"] == settings.metrics
      assert config["metricsJson"] == settings.metrics_json
      assert config["drawings"] == settings.drawings
      assert config["queries"] == settings.queries
      assert config["options"] == settings.options
      assert config["project"]["id"] |> String.to_integer() == project.id
      assert config["project"]["slug"] == project.slug
      assert config["user"]["id"] |> String.to_integer() == user.id
      assert config["user"]["email"] == user.email
      assert config["post"]["id"] == post.id
      assert config["post"]["title"] == post.title
    end

    test "update", context do
      %{conn: conn, settings: settings, user: user} = context

      config_id =
        create_chart_configuration(conn, settings)
        |> get_in(["data", "createChartConfiguration", "id"])

      new_post = insert(:post, user: user, title: "New Title")

      new_settings = %{
        title: "New Title",
        description: "New description",
        is_public: true,
        metrics: ["getMetric|nvt"],
        metrics_json: %{"price_btc" => %{"slug" => "bitcoin"}},
        anomalies: [],
        post_id: new_post.id,
        drawings: %{
          "circles" => [
            %{"cx" => 50, "cy" => 50, "r" => 20}
          ]
        },
        queries: %{
          "top_holders" => %{
            "query" => "top_holders",
            "args" => %{"slug" => "bitcoin", "from" => "utc_now-3d", "to" => "utc_now"},
            "selected_fields" => ["datetime", "trx_value", "trx_hash"]
          }
        },
        options: %{
          "multi_chart" => false,
          "log_scale" => true,
          "non_boolean_option" => 12
        }
      }

      config =
        update_chart_configuration(conn, config_id, new_settings)
        |> get_in(["data", "updateChartConfiguration"])

      assert config["title"] == new_settings.title
      assert config["description"] == new_settings.description
      assert config["isPublic"] == new_settings.is_public
      assert config["anomalies"] == new_settings.anomalies
      assert config["metrics"] == new_settings.metrics
      assert config["metricsJson"] == new_settings.metrics_json
      assert config["drawings"] == new_settings.drawings
      assert config["queries"] == new_settings.queries
      assert config["options"] == new_settings.options
      assert config["post"]["id"] == new_settings.post_id
      assert config["post"]["title"] == new_post.title
    end

    test "cannot update other user's configuration", context do
      %{conn: conn, conn2: conn2, settings: settings} = context

      config_id =
        create_chart_configuration(conn, settings)
        |> get_in(["data", "createChartConfiguration", "id"])

      error_msg =
        update_chart_configuration(conn2, config_id, %{title: "New Title"})
        |> get_in(["errors"])
        |> hd()
        |> Map.get("message")

      assert error_msg =~ "does not exist or is private"
    end

    test "delete", context do
      %{conn: conn, settings: settings} = context

      config_id =
        create_chart_configuration(conn, settings)
        |> get_in(["data", "createChartConfiguration", "id"])

      _ = delete_chart_configuration(conn, config_id)
      {:error, error_msg} = Sanbase.Chart.Configuration.by_id(config_id, [])
      assert error_msg =~ "does not exist"
    end
  end

  describe "chart configuration queries" do
    test "can query with anonymous user", context do
      %{conn: conn, conn_no_user: conn_no_user, settings: settings} = context

      # Create a public and private configuration

      config_id1 =
        create_chart_configuration(conn, %{settings | is_public: true})
        |> get_in(["data", "createChartConfiguration", "id"])

      config_id2 =
        create_chart_configuration(conn, %{settings | is_public: false})
        |> get_in(["data", "createChartConfiguration", "id"])

      # Test fetching configuratins with no logged in user

      config1 =
        get_chart_configuration(conn_no_user, config_id1)
        |> get_in(["data", "chartConfiguration"])

      assert config1["id"] == config_id1

      config2 =
        get_chart_configuration(conn_no_user, config_id2)
        |> get_in(["data", "chartConfiguration"])

      assert config2 == nil

      config_ids =
        get_chart_configurations(conn_no_user)
        |> get_in(["data", "chartConfigurations"])
        |> Enum.map(& &1["id"])

      assert config_ids == [config_id1]
    end

    test "can get all fields", context do
      %{user: user, conn: conn, project: project, post: post, settings: settings} = context

      config_id =
        create_chart_configuration(conn, settings)
        |> get_in(["data", "createChartConfiguration", "id"])

      config =
        get_chart_configuration(conn, config_id)
        |> get_in(["data", "chartConfiguration"])

      assert config["title"] == settings.title
      assert config["description"] == settings.description
      assert config["isPublic"] == settings.is_public
      assert config["anomalies"] == settings.anomalies
      assert config["metrics"] == settings.metrics
      assert config["metricsJson"] == settings.metrics_json
      assert config["drawings"] == settings.drawings
      assert config["queries"] == settings.queries
      assert config["project"]["id"] |> String.to_integer() == project.id
      assert config["project"]["slug"] == project.slug
      assert config["user"]["id"] |> String.to_integer() == user.id
      assert config["user"]["email"] == user.email
      assert config["post"]["id"] == post.id
      assert config["post"]["title"] == post.title
    end

    test "get own public configuration", context do
      %{conn: conn, settings: settings} = context
      settings = Map.put(settings, :is_public, true)

      config_id =
        create_chart_configuration(conn, settings)
        |> get_in(["data", "createChartConfiguration", "id"])

      config =
        get_chart_configuration(conn, config_id)
        |> get_in(["data", "chartConfiguration"])

      assert config["id"] == config_id
    end

    test "get own private configuration", context do
      %{conn: conn, settings: settings} = context
      settings = Map.put(settings, :is_public, true)

      config_id =
        create_chart_configuration(conn, settings)
        |> get_in(["data", "createChartConfiguration", "id"])

      config =
        get_chart_configuration(conn, config_id)
        |> get_in(["data", "chartConfiguration"])

      assert config["id"] == config_id
    end

    test "get other user's public configuration", context do
      %{conn: conn, conn2: conn2, settings: settings} = context
      settings = Map.put(settings, :is_public, true)

      config_id =
        create_chart_configuration(conn, settings)
        |> get_in(["data", "createChartConfiguration", "id"])

      config =
        get_chart_configuration(conn2, config_id)
        |> get_in(["data", "chartConfiguration"])

      assert config["id"] == config_id
    end

    test "cannot get other user's private configuration", context do
      %{conn: conn, conn2: conn2, settings: settings} = context
      settings = Map.put(settings, :is_public, true)

      config_id =
        create_chart_configuration(conn, settings)
        |> get_in(["data", "createChartConfiguration", "id"])

      error_msg =
        update_chart_configuration(conn2, config_id, %{title: "New Title"})
        |> get_in(["errors"])
        |> hd()
        |> Map.get("message")

      assert error_msg =~ "does not exist or is private"
    end

    test "get all chart configurations", context do
      %{conn: conn, conn2: conn2, settings: settings} = context
      settings = Map.put(settings, :is_public, true)

      [config_id1, config_id2, config_id3, config_id4] =
        [
          create_chart_configuration(conn, settings),
          create_chart_configuration(conn, settings),
          create_chart_configuration(conn2, settings),
          create_chart_configuration(conn2, settings |> Map.put(:is_public, false))
        ]
        |> Enum.map(&get_in(&1, ["data", "createChartConfiguration", "id"]))

      config_ids =
        get_chart_configurations(conn)
        |> get_in(["data", "chartConfigurations"])
        |> Enum.map(& &1["id"])

      assert config_id1 in config_ids
      assert config_id2 in config_ids
      assert config_id3 in config_ids
      refute config_id4 in config_ids
    end

    test "get all chart configurations of a user", context do
      %{conn: conn, conn2: conn2, user2: user2, settings: settings} = context
      settings = Map.put(settings, :is_public, true)

      [config_id1, config_id2, config_id3, config_id4] =
        [
          create_chart_configuration(conn, settings),
          create_chart_configuration(conn, settings),
          create_chart_configuration(conn2, settings),
          create_chart_configuration(conn2, %{settings | is_public: false})
        ]
        |> Enum.map(&get_in(&1, ["data", "createChartConfiguration", "id"]))

      # User gets their own public and private configurations
      config_ids =
        get_chart_configurations(conn2, user_id: user2.id)
        |> get_in(["data", "chartConfigurations"])
        |> Enum.map(& &1["id"])

      refute config_id1 in config_ids
      refute config_id2 in config_ids
      assert config_id3 in config_ids
      assert config_id4 in config_ids

      # Get only public configurations of another user
      config_ids =
        get_chart_configurations(conn, user_id: user2.id)
        |> get_in(["data", "chartConfigurations"])
        |> Enum.map(& &1["id"])

      assert length(config_ids) == 1
      assert config_id3 in config_ids
    end

    test "get all chart configurations for a project by project_id", context do
      %{conn: conn, conn2: conn2, project: project, project2: project2, settings: settings} =
        context

      settings = Map.put(settings, :is_public, true)

      [_, config_id2, config_id3, config_id4] =
        [
          create_chart_configuration(conn, %{settings | project_id: project.id}),
          create_chart_configuration(conn, %{settings | project_id: project2.id}),
          create_chart_configuration(conn2, %{settings | project_id: project2.id}),
          create_chart_configuration(conn2, %{
            settings
            | project_id: project2.id,
              is_public: false
          })
        ]
        |> Enum.map(&get_in(&1, ["data", "createChartConfiguration", "id"]))

      # Get all own and other users' public configurations for a project
      # Other users private configurations are hidden
      config_ids =
        get_chart_configurations(conn, project_id: project2.id)
        |> get_in(["data", "chartConfigurations"])
        |> Enum.map(& &1["id"])

      assert length(config_ids) == 2
      assert config_id2 in config_ids
      assert config_id3 in config_ids

      # Get all own and other users' public configurations for a project
      # Own private configurations are accessible
      config_ids =
        get_chart_configurations(conn2, project_id: project2.id)
        |> get_in(["data", "chartConfigurations"])
        |> Enum.map(& &1["id"])

      assert length(config_ids) == 3
      assert config_id2 in config_ids
      assert config_id3 in config_ids
      assert config_id4 in config_ids
    end

    test "get all chart configurations for a project by project_slug", context do
      %{conn: conn, conn2: conn2, project: project, project2: project2, settings: settings} =
        context

      settings = Map.put(settings, :is_public, true)

      [_, config_id2, config_id3, config_id4] =
        [
          create_chart_configuration(conn, %{settings | project_id: project.id}),
          create_chart_configuration(conn, %{settings | project_id: project2.id}),
          create_chart_configuration(conn2, %{settings | project_id: project2.id}),
          create_chart_configuration(conn2, %{
            settings
            | project_id: project2.id,
              is_public: false
          })
        ]
        |> Enum.map(&get_in(&1, ["data", "createChartConfiguration", "id"]))

      # Get all own and other users' public configurations for a project
      # Other users private configurations are hidden
      config_ids =
        get_chart_configurations(conn, project_slug: project2.slug)
        |> get_in(["data", "chartConfigurations"])
        |> Enum.map(& &1["id"])

      assert length(config_ids) == 2
      assert config_id2 in config_ids
      assert config_id3 in config_ids

      # Get all own and other users' public configurations for a project
      # Own private configurations are accessible
      config_ids =
        get_chart_configurations(conn2, project_slug: project2.slug)
        |> get_in(["data", "chartConfigurations"])
        |> Enum.map(& &1["id"])

      assert length(config_ids) == 3
      assert config_id2 in config_ids
      assert config_id3 in config_ids
      assert config_id4 in config_ids
    end

    test "returns error when both project_id and project_slug are provided", context do
      %{conn: conn, project: project, project2: project2} = context

      error_msg =
        get_chart_configurations(conn, project_slug: project.slug, project_id: project2.id)
        |> get_in(["errors", Access.at(0), "message"])

      assert error_msg ==
               "Both projectId and projectSlug arguments are provided. Please use only one of them or none."
    end

    test "get user's configurations for a given project", context do
      %{
        conn: conn,
        conn2: conn2,
        user: user,
        user2: user2,
        project: project,
        project2: project2,
        settings: settings
      } = context

      settings = Map.put(settings, :is_public, true)

      [_, _, config_id3, config_id4, _] =
        [
          create_chart_configuration(conn, %{settings | project_id: project.id}),
          create_chart_configuration(conn, %{settings | project_id: project.id}),
          create_chart_configuration(conn2, %{settings | project_id: project2.id}),
          create_chart_configuration(conn2, %{
            settings
            | project_id: project2.id,
              is_public: false
          }),
          create_chart_configuration(conn2, %{settings | project_id: project.id})
        ]
        |> Enum.map(&get_in(&1, ["data", "createChartConfiguration", "id"]))

      # No charts for a user and project
      config_ids =
        get_chart_configurations(conn, user_id: user.id, project_id: project2.id)
        |> get_in(["data", "chartConfigurations"])
        |> Enum.map(& &1["id"])

      assert config_ids == []

      # Get all public configurations of a user for a given project
      config_ids =
        get_chart_configurations(conn, user_id: user2.id, project_id: project2.id)
        |> get_in(["data", "chartConfigurations"])
        |> Enum.map(& &1["id"])

      assert length(config_ids) == 1
      assert config_id3 in config_ids

      # Get all own public and private configurations for a given project
      config_ids =
        get_chart_configurations(conn2, user_id: user2.id, project_id: project2.id)
        |> get_in(["data", "chartConfigurations"])
        |> Enum.map(& &1["id"])

      assert length(config_ids) == 2
      assert config_id3 in config_ids
      assert config_id4 in config_ids
    end
  end

  test "get chart events", context do
    conf = insert(:chart_configuration, is_public: true)

    args = %{
      is_chart_event: true,
      chart_configuration_for_event_id: conf.id,
      chart_event_datetime: DateTime.utc_now(),
      title: "chart event"
    }

    insert(:post, args)
    insert(:post, args)

    res = get_chart_configuration(context.conn, conf.id) |> get_in(["data", "chartConfiguration"])
    assert length(res["chartEvents"]) == 2
  end

  # Private functions

  defp create_chart_configuration(conn, settings) do
    query = """
    mutation {
      createChartConfiguration(settings: #{map_to_input_object_str(settings)}) {
        id
        title
        isPublic
        description
        user{ id email }
        project{ id slug }
        post{ id title }
        metrics
        metricsJson
        anomalies
        queries
        drawings
        options
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(query))
    |> json_response(200)
  end

  defp update_chart_configuration(conn, config_id, settings) do
    query = """
    mutation {
      updateChartConfiguration(id: #{config_id}, settings: #{map_to_input_object_str(settings)}) {
        id
        title
        isPublic
        description
        user{ id email }
        project{ id slug }
        post{ id title }
        metrics
        metricsJson
        anomalies
        queries
        drawings
        options
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(query))
    |> json_response(200)
  end

  defp delete_chart_configuration(conn, config_id) do
    query = """
    mutation {
      deleteChartConfiguration(id: #{config_id}) {
        id
        title
        isPublic
        description
        user{ id email }
        project{ id slug }
        post{ id title }
        metrics
        metricsJson
        anomalies
        queries
        drawings
        options
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(query))
    |> json_response(200)
  end

  defp get_chart_configuration(conn, config_id) do
    query = """
    {
      chartConfiguration(id: #{config_id}) {
        id
        title
        isPublic
        description
        user{ id email }
        project{ id slug }
        post{ id title }
        metrics
        metricsJson
        anomalies
        queries
        drawings
        chartEvents {
          id
          isChartEvent
          chartEventDatetime
          title
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp get_chart_configurations(conn, opts \\ [])

  defp get_chart_configurations(conn, []) do
    query = """
    {
      chartConfigurations {
        id
        title
        isPublic
        description
        user{ id email }
        project{ id slug }
        post{ id title }
        metrics
        metricsJson
        queries
        anomalies
        drawings
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp get_chart_configurations(conn, opts) do
    user_id = Keyword.get(opts, :user_id)
    project_id = Keyword.get(opts, :project_id)
    project_slug = Keyword.get(opts, :project_slug)

    query = """
    {
      chartConfigurations(
        #{if user_id, do: "userId: #{user_id}"}
        #{if project_id, do: "projectId: #{project_id}"}
        #{if project_slug, do: "projectSlug: \"#{project_slug}\""}
      ) {
        id
        title
        isPublic
        description
        user{ id email }
        project{ id slug }
        post{ id title }
        metrics
        metricsJson
        anomalies
        queries
        drawings
        options
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
