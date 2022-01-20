defmodule SanbaseWeb.Graphql.UpdateTriggerApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, user: user}
  end

  test "cannot update others' featured trigger", context do
    # create a trigger for a random new user
    user_trigger = insert(:user_trigger)
    Sanbase.FeaturedItem.update_item(user_trigger, true)

    result = update_trigger(context.conn, trigger_id: user_trigger.id, is_active: true)

    assert result["errors"] |> List.first() |> Map.get("message") ==
             "The trigger with id #{user_trigger.id} does not exists or does not belong to the current user"
  end

  defp update_trigger(conn, opts) do
    trigger_id = Keyword.fetch!(opts, :trigger_id)
    is_active = Keyword.fetch!(opts, :is_active)

    query = """
    mutation {
      updateTrigger(
        id: #{trigger_id}
        isActive: #{is_active}
      ) {
        trigger{ isActive }
      }
    }
    """

    conn
    |> post("/graphql", %{"query" => query})
    |> json_response(200)
  end
end
