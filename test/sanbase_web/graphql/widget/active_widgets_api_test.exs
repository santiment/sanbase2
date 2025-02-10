defmodule SanbaseWeb.Graphql.ActiveWidgetsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  test "fetcha active widgets", %{conn: conn} do
    widget = insert(:active_widget, is_active: true)
    insert(:active_widget, is_active: false)
    insert(:active_widget, is_active: false)
    insert(:active_widget, is_active: false)

    query = """
    {
      activeWidgets {
        title
        description
        videoLink
        imageLink
        createdAt
      }
    }
    """

    [result | rest] =
      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)
      |> get_in(["data", "activeWidgets"])

    assert rest == []
    assert result["title"] == widget.title
    assert result["description"] == widget.description
    assert result["videoLink"] == widget.video_link
    assert result["imageLink"] == widget.image_link

    assert result["createdAt"] ==
             widget.inserted_at
             |> DateTime.from_naive!("Etc/UTC")
             |> DateTime.truncate(:second)
             |> DateTime.to_iso8601()
  end
end
