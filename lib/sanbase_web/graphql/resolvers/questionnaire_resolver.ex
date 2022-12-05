defmodule SanbaseWeb.Graphql.Resolvers.QuestionnaireResolver do
  alias Sanbase.Questionnaire

  def get_questionnaire(_root, %{questionnaire_uuid: questionnaire_uuid}, _resolution) do
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
    Questionnaire.create(params)
  end

  def update_questionnaire(
        _root,
        %{questionnaire_uuid: questionnaire_uuid, params: params},
        _resolution
      ) do
    Questionnaire.update(questionnaire_uuid, params)
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

  def update_question(_root, %{question_uuid: question_uuid, params: params}, _resolution) do
    case Questionnaire.update_question(question_uuid, params) do
      {:ok, question} -> Questionnaire.by_uuid(question.questionnaire_uuid)
      {:error, error} -> {:error, error}
    end
  end

  def create_answer(_root, %{question_uuid: question_uuid, params: params}, %{
        context: %{auth: %{current_user: user}}
      }) do
    Questionnaire.create_answer(question_uuid, user.id, params)
  end

  def update_answer(_root, %{question_uuid: question_uuid, params: params}, %{
        context: %{auth: %{current_user: user}}
      }) do
    Questionnaire.update_answer(question_uuid, user.id, params)
  end

  def delete_answer(_root, %{question_uuid: question_uuid}, %{
        context: %{auth: %{current_user: user}}
      }) do
    Questionnaire.delete_answer(question_uuid, user.id)
  end
end
