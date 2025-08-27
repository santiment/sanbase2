defmodule SanbaseWeb.Graphql.MCPInsightTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers, only: [try_few_times: 2]

  setup do
    user = insert(:user, username: "santiment_user")
    {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)

    port = Sanbase.Utils.Config.module_get(SanbaseWeb.Endpoint, [:http, :port])

    {:ok, _client} =
      Sanbase.MCP.Client.start_link(
        transport:
          {:streamable_http,
           [
             base_url: "http://localhost:#{port}",
             headers: %{
               "authorization" => "Apikey #{apikey}",
               "content-type" => "application/json",
               "host" => "localhost:#{port}"
             }
           ]},
        client_info: %{"name" => "SanbaseTestMCPClient", "version" => "1.0.0"},
        capabilities: %{"tools" => %{}},
        protocol_version: "2025-03-26"
      )

    tag1 = insert(:tag, name: "TAG1")
    tag2 = insert(:tag, name: "TAG2")

    i1 =
      insert(:published_post,
        user: user,
        title: "Title1",
        text: "Text1",
        tags: [tag1],
        published_at: DateTime.utc_now()
      )

    i2 =
      insert(:published_post,
        user: user,
        title: "Title2",
        text: "Text2",
        tags: [tag1, tag2],
        published_at: DateTime.utc_now() |> DateTime.add(-4, :day)
      )

    insert(:published_post,
      user: user,
      title: "Title3",
      text: "Text3",
      tags: [tag1],
      published_at: DateTime.utc_now() |> DateTime.add(-10, :day)
    )

    %{user: user, apikey: apikey, insight1: i1, insight2: i2}
  end

  test "insights_discovery", _context do
    result =
      try_few_times(
        fn -> Sanbase.MCP.Client.call_tool("insight_discovery_tool", %{time_period: "7d"}) end,
        attempts: 3,
        sleep: 250
      )

    assert {:ok,
            %Anubis.MCP.Response{
              result: %{
                "content" => [
                  %{
                    "text" => json,
                    "type" => "text"
                  }
                ],
                "isError" => false
              },
              id: "req_" <> _,
              method: "tools/call",
              is_error: false
            }} = result

    assert {:ok, result} = Jason.decode(json)

    assert %{
             "insights" => [
               %{
                 "title" => "Title1",
                 "author" => "santiment_user",
                 "id" => _,
                 "link" => _,
                 "prediction" => "unspecified",
                 "published_at" => _,
                 "tags" => ["TAG1"]
               },
               %{
                 "title" => "Title2",
                 "author" => "santiment_user",
                 "id" => _,
                 "link" => _,
                 "prediction" => "unspecified",
                 "published_at" => _,
                 "tags" => ["TAG1", "TAG2"]
               }
             ],
             "period_end" => _,
             "period_start" => _,
             "time_period" => "7d",
             "total_count" => 2
           } = result
  end

  test "insights fetch", context do
    {:ok, result} =
      try_few_times(
        fn ->
          Sanbase.MCP.Client.call_tool("fetch_insights_tool", %{
            insight_ids: [context.insight1.id, context.insight2.id]
          })
        end,
        attempts: 3,
        sleep: 250
      )

    {:ok, result2} =
      try_few_times(
        fn ->
          Sanbase.MCP.Client.call_tool("fetch_insights_tool", %{
            insight_ids: "[#{context.insight1.id}, #{context.insight2.id}]"
          })
        end,
        attempts: 3,
        sleep: 250
      )

    # Check that both providing a list and a JSON list is understood
    assert result.result == result2.result

    assert %Anubis.MCP.Response{
             result: %{
               "content" => [
                 %{
                   "text" => json,
                   "type" => "text"
                 }
               ],
               "isError" => false
             },
             id: "req_" <> _,
             method: "tools/call",
             is_error: false
           } = result

    data = Jason.decode!(json)

    assert %{
             "insights" => [
               %{
                 "author" => %{"username" => "santiment_user"},
                 "id" => id1,
                 "link" => _,
                 "metrics" => _,
                 "prediction" => "unspecified",
                 "published_at" => _,
                 "tags" => ["TAG1"],
                 "text" => "Text1",
                 "title" => "Title1"
               },
               %{
                 "author" => %{"username" => "santiment_user"},
                 "id" => id2,
                 "link" => _,
                 "metrics" => _,
                 "prediction" => "unspecified",
                 "published_at" => _,
                 "tags" => ["TAG1", "TAG2"],
                 "text" => "Text2",
                 "title" => "Title2"
               }
             ],
             "requested_ids" => requested_ids,
             "total_count" => 2
           } = data

    assert context.insight1.id == id1
    assert context.insight2.id == id2
    assert requested_ids == [context.insight1.id, context.insight2.id]
  end
end
