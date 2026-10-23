defmodule SanbaseWeb.Graphql.PaywalledInsightsDocumentCacheTest do
  # Not async: storing in the document cache is switched on through global app env.
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  @before_send SanbaseWeb.Graphql.AbsintheBeforeSend

  setup do
    # The document cache stores results only when API call exporting is enabled,
    # which is always the case outside of the test env.
    Application.put_env(@before_send, :api_call_exporting_enabled, true)
    on_exit(fn -> Application.delete_env(@before_send, :api_call_exporting_enabled) end)

    author = insert(:user)
    text = Stream.cycle(["alabala"]) |> Enum.take(200) |> Enum.join(" ")

    insert(:published_post,
      user: author,
      text: text,
      is_paywall_required: true,
      published_at: DateTime.utc_now()
    )

    %{author: author, text: text}
  end

  test "the paywall applies to the author in a cached feed", context do
    query = most_recent_query("")

    assert [author_text] = most_recent_texts(context.author, query)
    assert author_text != context.text
    assert author_text =~ "alabala"

    assert [other_text] = most_recent_texts(insert(:user), query)
    assert other_text == author_text
  end

  test "the author sees the full text when fetching only their own entities", context do
    query = most_recent_query("currentUserDataOnly: true")

    assert [author_text] = most_recent_texts(context.author, query)
    assert author_text == context.text
  end

  test "a user with access sees the full text in a cached feed", context do
    pro_user = insert(:user)
    insert(:subscription_pro_sanbase, user: pro_user)

    assert [pro_text] = most_recent_texts(pro_user, most_recent_query(""))
    assert pro_text == context.text
  end

  defp most_recent_query(extra_args) do
    """
    {
      getMostRecent(types: [INSIGHT], page: 1, pageSize: 10 #{extra_args}) {
        data { insight { text } }
      }
    }
    """
  end

  defp most_recent_texts(user, query) do
    setup_jwt_auth(build_conn(), user)
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "getMostRecent", "data"])
    |> Enum.map(& &1["insight"]["text"])
  end
end
