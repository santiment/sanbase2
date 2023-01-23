defmodule Sanbase.QuestionnaireTest do
  use Sanbase.DataCase, async: true

  import Sanbase.Factory

  alias Sanbase.Questionnaire

  describe "create/update/delete questionnaire" do
    test "create" do
      ends_at = DateTime.utc_now() |> DateTime.add(86400, :second)

      assert {:ok, questionnaire} =
               Questionnaire.create(%{
                 name: "SQL Questions",
                 description: "Description",
                 ends_at: ends_at
               })

      assert {:ok, fetched} = Questionnaire.by_uuid(questionnaire.uuid)

      assert questionnaire.uuid == fetched.uuid
      assert questionnaire.name == fetched.name
      assert questionnaire.description == fetched.description
      assert questionnaire.ends_at == fetched.ends_at
    end

    test "update" do
      {:ok, questionnaire} = create_questionnaire()

      {:ok, questionnaire} =
        Questionnaire.update(questionnaire.uuid, %{
          name: "new name",
          description: "new description",
          ends_at: ~U[2030-01-01 00:00:00Z]
        })

      assert questionnaire.name == "new name"
      assert questionnaire.description == "new description"
      assert questionnaire.ends_at == ~U[2030-01-01 00:00:00Z]
    end

    test "delete" do
      {:ok, questionnaire} = create_questionnaire()
      {:ok, _} = Questionnaire.delete(questionnaire.uuid)
      assert {:error, _} = Questionnaire.by_uuid(questionnaire.uuid)
    end
  end

  describe "create/update/delete questionnaire's questions" do
    test "create" do
      {:ok, questionnaire} = create_questionnaire()

      {:ok, _question} =
        Questionnaire.create_question(questionnaire.uuid, %{
          order: 1,
          question: "How are you?",
          type: :open_text
        })

      {:ok, _question} =
        Questionnaire.create_question(questionnaire.uuid, %{
          order: 2,
          question: "How old are you?",
          type: :open_number
        })

      {:ok, questionnaire} = Questionnaire.by_uuid(questionnaire.uuid)

      assert length(questionnaire.questions) == 2

      q1 = Enum.at(questionnaire.questions, 0)
      assert q1.order == 1
      assert q1.question == "How are you?"
      assert q1.type == :open_text

      q2 = Enum.at(questionnaire.questions, 1)
      assert q2.order == 2
      assert q2.question == "How old are you?"
      assert q2.type == :open_number
    end

    test "update" do
      {:ok, questionnaire} = create_questionnaire()
      {:ok, question} = create_question(questionnaire.uuid)

      {:ok, question} = Questionnaire.update_question(question.uuid, %{question: "Updated?"})

      {:ok, questionnaire} = Questionnaire.by_uuid(questionnaire.uuid)

      assert question.question == "Updated?"
      assert Enum.at(questionnaire.questions, 0).question == "Updated?"
    end

    test "delete" do
      {:ok, questionnaire} = create_questionnaire()
      {:ok, question} = create_question(questionnaire.uuid)
      {:ok, _question} = Questionnaire.delete_question(question.uuid)
      {:ok, questionnaire} = Questionnaire.by_uuid(questionnaire.uuid)

      assert questionnaire.questions == []
    end
  end

  describe "create/update/delete questionnaire's answers" do
    setup do
      {:ok, questionnaire} = create_questionnaire()
      {:ok, question} = create_question(questionnaire.uuid)
      {:ok, question2} = create_question(questionnaire.uuid, %{order: 2})

      %{
        user: insert(:user),
        user2: insert(:user),
        questionnaire: questionnaire,
        question: question,
        question2: question2
      }
    end

    test "create", context do
      %{user: user, user2: user2} = context

      %{questionnaire: questionnaire, question: question, question2: question2} = context

      {:ok, _} =
        Questionnaire.create_answer(question.uuid, user.id, %{
          answer: %{"open_text_answer" => "Good"}
        })

      {:ok, _} =
        Questionnaire.create_answer(question.uuid, user2.id, %{
          answer: %{"open_text_answer" => "Bad"}
        })

      {:ok, _} =
        Questionnaire.create_answer(question2.uuid, user2.id, %{
          answer: %{"open_text_answer" => "The same"}
        })

      {:ok, user_answers} = Questionnaire.user_answers(questionnaire.uuid, user.id)

      {:ok, user2_answers} = Questionnaire.user_answers(questionnaire.uuid, user2.id)

      assert length(user_answers) == 1
      assert length(user2_answers) == 2
    end

    test "create multiple answers to the same question updates the old answer", context do
      %{user: user, questionnaire: questionnaire, question: question} = context

      {:ok, answer1} =
        Questionnaire.create_answer(question.uuid, user.id, %{
          answer: %{"open_text_answer" => "Good"}
        })

      {:ok, answer2} =
        Questionnaire.create_answer(question.uuid, user.id, %{
          answer: %{"open_text_answer" => "Good 2"}
        })

      {:ok, user_answers} = Questionnaire.user_answers(questionnaire.uuid, user.id)

      assert length(user_answers) == 1
      [answer] = user_answers

      assert answer1.uuid == answer2.uuid
      assert answer.answer == %{"open_text_answer" => "Good 2"}
    end

    test "update", context do
      %{user: user, questionnaire: questionnaire, question: question} = context

      {:ok, answer} =
        Questionnaire.create_answer(question.uuid, user.id, %{
          answer: %{"open_text_answer" => "Good"}
        })

      {:ok, answer} =
        Questionnaire.update_answer(answer.uuid, user.id, %{
          answer: %{"open_text_answer" => "Updated good."}
        })

      assert answer.answer == %{"open_text_answer" => "Updated good."}

      {:ok, user_answers} = Questionnaire.user_answers(questionnaire.uuid, user.id)

      [answer] = user_answers
      assert answer.answer == %{"open_text_answer" => "Updated good."}
    end

    test "delete", context do
      %{user: user, questionnaire: questionnaire, question: question} = context

      {:ok, answer} =
        Questionnaire.create_answer(question.uuid, user.id, %{
          answer: %{"open_text_answer" => "Good"}
        })

      {:ok, _} = Questionnaire.delete_answer(answer.uuid, user.id)

      assert {:ok, []} == Questionnaire.user_answers(questionnaire.uuid, user.id)
    end
  end

  defp create_questionnaire(params \\ %{}) do
    ends_in = Map.get(params, :ends_in, 86400)
    ends_at = DateTime.utc_now() |> DateTime.add(ends_in, :second)

    Questionnaire.create(%{
      name: Map.get(params, :name, "SQL Questions"),
      description: Map.get(params, :description, "Description"),
      ends_at: ends_at
    })
  end

  defp create_question(questionnaire_uuid, params \\ %{}) do
    Questionnaire.create_question(questionnaire_uuid, %{
      question: Map.get(params, :question, "How are you?"),
      order: Map.get(params, :question, 1),
      type: Map.get(params, :type, :open_text)
    })
  end
end
