defmodule SanbaseWeb.Graphql.QuestionnaireInvalidUuidApiTest do
  use SanbaseWeb.ConnCase, async: true

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn}
  end

  test "Questionnaire.by_uuid/1 with a non-UUID returns an error tuple" do
    assert {:error, "Questionnaire with uuid bitcoin does not exist"} =
             Sanbase.Questionnaire.by_uuid("bitcoin")
  end

  for field <- ["getQuestionnaire", "getQuestionnaireUserAnswers"] do
    test "#{field} with a non-UUID returns an error", %{conn: conn} do
      query = """
      {
        #{unquote(field)}(questionnaireUuid: "bitcoin") { uuid }
      }
      """

      assert execute_query_with_error(conn, query) ==
               "Questionnaire with uuid bitcoin does not exist"
    end
  end
end
