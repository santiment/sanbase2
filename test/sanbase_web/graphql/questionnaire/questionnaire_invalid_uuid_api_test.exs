defmodule SanbaseWeb.Graphql.QuestionnaireInvalidUuidApiTest do
  # Reproduces SANBASE-BACKEND-PROD-GA1: a non-UUID questionnaireUuid reaches
  # Ecto uncast in Sanbase.Questionnaire.by_uuid/1 and raises
  # Ecto.Query.CastError (500) instead of a GraphQL error.
  use SanbaseWeb.ConnCase, async: true

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn}
  end

  test "Questionnaire.by_uuid/1 with a non-UUID returns an error tuple" do
    assert {:error, error} = Sanbase.Questionnaire.by_uuid("bitcoin")
    assert is_binary(error)
  end

  test "getQuestionnaire with a non-UUID returns an error", %{conn: conn} do
    query = """
    {
      getQuestionnaire(questionnaireUuid: "bitcoin") { uuid }
    }
    """

    result = execute_query(conn, query)

    assert get_in(result, ["data", "getQuestionnaire"]) == nil
    assert [%{"message" => message} | _] = result["errors"]
    assert is_binary(message)
  end

  test "getQuestionnaireUserAnswers with a non-UUID does not crash", %{conn: conn} do
    query = """
    {
      getQuestionnaireUserAnswers(questionnaireUuid: "bitcoin") { uuid }
    }
    """

    result = execute_query(conn, query)

    # Either a clean GraphQL error or an empty list is acceptable - just not a 500.
    case result do
      %{"errors" => [%{"message" => message} | _]} -> assert is_binary(message)
      _ -> assert get_in(result, ["data", "getQuestionnaireUserAnswers"]) == []
    end
  end
end
