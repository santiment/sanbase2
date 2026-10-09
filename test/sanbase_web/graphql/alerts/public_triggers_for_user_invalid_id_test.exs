defmodule SanbaseWeb.Graphql.PublicTriggersForUserInvalidIdTest do
  # Reproduces SANBASE-BACKEND-PROD-GAY: a non-integer userId reaches Ecto
  # uncast in UserTrigger.public_user_triggers_for/1 and raises
  # Ecto.Query.CastError (500) instead of a GraphQL error / empty list.
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers

  for user_id <- ["ncMUFCMU", "1 OR 1"] do
    test "publicTriggersForUser with userId #{inspect(user_id)} does not crash" do
      query = """
      {
        publicTriggersForUser(userId: "#{unquote(user_id)}") {
          userId
          trigger { id }
        }
      }
      """

      result = execute_query(build_conn(), query)

      case result do
        %{"errors" => [%{"message" => message} | _]} -> assert is_binary(message)
        _ -> assert get_in(result, ["data", "publicTriggersForUser"]) == []
      end
    end
  end
end
