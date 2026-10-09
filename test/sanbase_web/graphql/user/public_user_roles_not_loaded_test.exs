defmodule SanbaseWeb.Graphql.PublicUserRolesNotLoadedTest do
  # Reproduces SANBASE-BACKEND-PROD-GAR: UserResolver.moderator?/3 and
  # santiment_team_member?/3 call Enum.any?/2 on `user.roles`. When the
  # :public_user comes from a plain `preload: [:user]` (e.g. sql_query.user via
  # getPublicQueries) the roles association is not loaded and the resolver
  # raises Protocol.UndefinedError (500).
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    moderator = insert(:user)
    role = insert(:role_san_moderator)
    {:ok, _} = Sanbase.Accounts.UserRole.create(moderator.id, role.id)

    insert(:query, %{user: user, is_public: true, name: "Public query 1"})
    insert(:query, %{user: moderator, is_public: true, name: "Public query 2"})

    %{user: user, moderator: moderator}
  end

  test "getPublicQueries { user { isModerator isSantimentTeamMember } } works", context do
    query = """
    {
      getPublicQueries(page: 1, pageSize: 10) {
        name
        user { id isModerator isSantimentTeamMember }
      }
    }
    """

    result = execute_query(build_conn(), query)

    refute Map.has_key?(result, "errors")
    queries = get_in(result, ["data", "getPublicQueries"])
    assert length(queries) == 2

    by_user_id = Map.new(queries, fn q -> {q["user"]["id"], q["user"]} end)

    assert %{"isModerator" => false, "isSantimentTeamMember" => false} =
             by_user_id[to_string(context.user.id)]

    assert %{"isModerator" => true} = by_user_id[to_string(context.moderator.id)]
  end
end
