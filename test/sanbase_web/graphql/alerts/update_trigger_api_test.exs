defmodule SanbaseWeb.Graphql.UpdateTriggerApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    user2 = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, user: user, user2: user2}
  end

  test "cannot update other users' triggers", context do
    %{conn: conn, user2: user2} = context
    # create a trigger for a random new user
    user_trigger = insert(:user_trigger, user: user2)

    result = update_trigger(conn, trigger_id: user_trigger.id, is_active: false)

    assert result["errors"] |> List.first() |> Map.get("message") ==
             "The trigger with id #{user_trigger.id} does not exists or does not belong to the current user"
  end

  test "cannot update frozen triggers", context do
    %{conn: conn, user: user} = context
    # create a trigger for a random new user
    user_trigger = insert(:user_trigger, user: user)

    {:ok, _} =
      Sanbase.Alert.UserTrigger.update_user_trigger(user.id, %{
        id: user_trigger.id,
        is_frozen: true
      })

    result = update_trigger(conn, trigger_id: user_trigger.id, is_active: false)

    assert result["errors"] |> List.first() |> Map.get("message") ==
             "The trigger with id #{user_trigger.id} is frozen"
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
