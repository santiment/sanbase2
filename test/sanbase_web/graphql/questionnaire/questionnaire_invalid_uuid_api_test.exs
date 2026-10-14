defmodule SanbaseWeb.Graphql.QuestionnaireInvalidUuidApiTest do
  use SanbaseWeb.ConnCase, async: true

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.Questionnaire.{Answer, Question}

  test "Question.by_uuid/1 with a non-UUID returns an error tuple" do
    assert Question.by_uuid("bitcoin") ==
             {:error, "No questionnaire question with id bitcoin exists"}
  end

  test "Answer.update/3 and Answer.delete/2 with a non-UUID return an error tuple" do
    assert {:error, update_error} = Answer.update("bitcoin", 1, %{})
    assert update_error =~ "with uuid bitcoin does not exist"

    assert {:error, delete_error} = Answer.delete("bitcoin", 1)
    assert delete_error =~ "with uuid bitcoin does not exist"
  end

  for field <- ["getQuestionnaire", "getQuestionnaireUserAnswers"] do
    test "#{field} with a non-UUID returns an error" do
      conn = setup_jwt_auth(build_conn(), insert(:user))

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
