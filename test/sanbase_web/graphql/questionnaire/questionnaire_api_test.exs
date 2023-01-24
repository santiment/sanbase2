defmodule SanbaseWeb.Graphql.QuestionnaireApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    moderator = insert(:user)

    role = insert(:role_san_moderator)
    assert {:ok, _} = Sanbase.Accounts.UserRole.create(moderator.id, role.id)

    conn = setup_jwt_auth(build_conn(), user)
    moderator_conn = setup_jwt_auth(build_conn(), moderator)

    %{conn: conn, moderator_conn: moderator_conn}
  end

  test "full", %{conn: conn, moderator_conn: moderator_conn} do
    # Create a questionnaire
    questionnaire =
      create_questionnaire(moderator_conn, %{name: "Name", description: "Descr"})
      |> get_in(["data", "createQuestionnaire"])

    # Add some questions
    create_questionnaire_question(moderator_conn, questionnaire["uuid"], %{
      question: "How are you?",
      type: :open_text,
      order: 1
    })
    |> get_in(["data", "createQuestionnaireQuestion"])

    create_questionnaire_question(moderator_conn, questionnaire["uuid"], %{
      question: "Select the correct answer",
      type: :single_select,
      answer_options:
        %{"1" => "Not correct", "2" => "Correct", "3" => "Also not correct"} |> Jason.encode!(),
      order: 2
    })
    |> get_in(["data", "createQuestionnaireQuestion"])

    # Assert the question are fetchable
    questionnaire =
      get_questionnaire(conn, questionnaire["uuid"])
      |> get_in(["data", "getQuestionnaire"])

    assert %{
             "questions" => [
               %{
                 "answerOptions" => %{},
                 "hasExtraOpenTextAnswer" => false,
                 "order" => 1,
                 "question" => "How are you?",
                 "type" => "OPEN_TEXT",
                 "uuid" => question1_uuid
               },
               %{
                 "answerOptions" => %{
                   "1" => "Not correct",
                   "2" => "Correct",
                   "3" => "Also not correct"
                 },
                 "hasExtraOpenTextAnswer" => false,
                 "order" => 2,
                 "question" => "Select the correct answer",
                 "type" => "SINGLE_SELECT",
                 "uuid" => question2_uuid
               }
             ]
           } = questionnaire

    # Give answer to the questions
    create_questionnaire_answer(conn, question1_uuid, %{answer: %{open_text_answer: "Good"}})

    create_questionnaire_answer(conn, question2_uuid, %{answer: %{answer_selection: "2"}})

    # Get the user answers

    user_answers =
      get_questionnaire_user_answers(conn, questionnaire["uuid"])
      |> get_in(["data", "getQuestionnaireUserAnswers"])

    # Check the recorded user answers
    assert length(user_answers) == 2

    assert %{
             "answer" => %{"open_text_answer" => "Good"},
             "question" => %{"question" => "How are you?", "type" => "OPEN_TEXT"}
           } in user_answers

    assert %{
             "answer" => %{"answer_selection" => "2"},
             "question" => %{"question" => "Select the correct answer", "type" => "SINGLE_SELECT"}
           } in user_answers
  end

  # Private functions

  defp get_questionnaire(conn, questionnaire_uuid) do
    query = """
    {
      getQuestionnaire(questionnaireUuid: "#{questionnaire_uuid}"){
        uuid
        questions{
          uuid
          question
          order
          type
          answerOptions
          hasExtraOpenTextAnswer
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp get_questionnaire_user_answers(conn, questionnaire_uuid) do
    query = """
    {
      getQuestionnaireUserAnswers(questionnaireUuid: "#{questionnaire_uuid}"){
        question { question type }
        answer
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp create_questionnaire(conn, params) do
    mutation = """
    mutation {
      createQuestionnaire(params: #{map_to_input_object_str(params)}) {
        uuid
        name
        description
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  defp create_questionnaire_question(conn, questionnaire_uuid, params) do
    mutation = """
    mutation {
      createQuestionnaireQuestion(questionnaireUuid: "#{questionnaire_uuid}", params: #{map_to_input_object_str(params)}) {
        uuid
        questions{
          question
          type
          answerOptions
          hasExtraOpenTextAnswer
        }
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  defp create_questionnaire_answer(conn, question_uuid, params) do
    mutation = """
    mutation {
      createQuestionnaireAnswer(questionUuid: "#{question_uuid}", params: #{map_to_input_object_str(params)}) {
        uuid
        question { question }
        answer
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end
end
