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

  test "Question.by_uuid/1 with a non-UUID returns an error tuple" do
    assert Sanbase.Questionnaire.Question.by_uuid("bitcoin") ==
             {:error, "No questionnaire question with id bitcoin exists"}
  end

  for fun <- [:update, :delete] do
    test "Answer.#{fun} with a non-UUID returns an error tuple" do
      args = if unquote(fun) == :update, do: ["bitcoin", 1, %{}], else: ["bitcoin", 1]

      assert {:error, "Anaswer with uuid bitcoin does not exist" <> _} =
               apply(Sanbase.Questionnaire.Answer, unquote(fun), args)
    end
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
