defmodule SanbaseWeb.Graphql.Resolvers.QuestionnaireResolver do
  alias Sanbase.Questionnaire

  def get_questionnaire(
        _root,
        %{questionnaire_uuid: questionnaire_uuid},
        _resolution
      ) do
    Questionnaire.by_uuid(questionnaire_uuid)
  end

  def get_questionnaire_user_answers(
        _root,
        %{questionnaire_uuid: questionnaire_uuid},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Questionnaire.user_answers(questionnaire_uuid, user.id)
  end

  def create_questionnaire(_root, %{params: params}, _resolution) do
    case Questionnaire.create(params) do
      # So the questions association is preloaded
      {:ok, questionnaire} -> Questionnaire.by_uuid(questionnaire.uuid)
      {:error, error} -> {:error, error}
    end
  end

  def update_questionnaire(
        _root,
        %{questionnaire_uuid: questionnaire_uuid, params: params},
        _resolution
      ) do
    case Questionnaire.update(questionnaire_uuid, params) do
      # So the questions association is preloaded
      {:ok, questionnaire} -> Questionnaire.by_uuid(questionnaire.uuid)
      {:error, error} -> {:error, error}
    end
  end

  def delete_questionnaire(
        _root,
        %{questionnaire_uuid: questionnaire_uuid},
        _resolution
      ) do
    # Return the first fetched struct so the returned result can have
    # all the questions preloaded
    with {:ok, questionnaire} <- Questionnaire.by_uuid(questionnaire_uuid),
         {:ok, _} <- Questionnaire.delete(questionnaire_uuid) do
      {:ok, questionnaire}
    end
  end

  def create_question(
        _root,
        %{questionnaire_uuid: questionnaire_uuid, params: params},
        _resolution
      ) do
    case Questionnaire.create_question(questionnaire_uuid, params) do
      {:ok, _} -> Questionnaire.by_uuid(questionnaire_uuid)
      {:error, error} -> {:error, error}
    end
  end

  def update_question(
        _root,
        %{question_uuid: question_uuid, params: params},
        _resolution
      ) do
    case Questionnaire.update_question(question_uuid, params) do
      {:ok, question} -> Questionnaire.by_uuid(question.questionnaire_uuid)
      {:error, error} -> {:error, error}
    end
  end

  def delete_question(_root, %{question_uuid: question_uuid}, _resolution) do
    case Questionnaire.delete_question(question_uuid) do
      {:ok, question} -> Questionnaire.by_uuid(question.questionnaire_uuid)
      {:error, error} -> {:error, error}
    end
  end

  def create_answer(_root, %{question_uuid: question_uuid, params: params}, %{
        context: %{auth: %{current_user: user}}
      }) do
    Questionnaire.create_answer(question_uuid, user.id, params)
  end

  def update_answer(_root, %{answer_uuid: answer_uuid, params: params}, %{
        context: %{auth: %{current_user: user}}
      }) do
    Questionnaire.update_answer(answer_uuid, user.id, params)
  end

  def delete_answer(_root, %{answer_uuid: answer_uuid}, %{
        context: %{auth: %{current_user: user}}
      }) do
    Questionnaire.delete_answer(answer_uuid, user.id)
  end
end
