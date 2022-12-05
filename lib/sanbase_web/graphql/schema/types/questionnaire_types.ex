defmodule SanbaseWeb.Graphql.QuestionnaireTypes do
  use Absinthe.Schema.Notation

  enum :question_type do
    value(:single_select)
    value(:multiple_select)
    value(:open_text)
    value(:open_number)
    value(:boolean)
  end

  object :questionnaire_question do
    field(:uuid, non_null(:string))
    field(:order, non_null(:integer))
    field(:question, non_null(:string))
    field(:type, non_null(:question_type))
    field(:answer_options, non_null(:json))
    field(:has_extra_open_text_answer, non_null(:boolean))
  end

  object :questionnaire_answer do
    field(:uuid, non_null(:string))
    field(:answer, non_null(:json))
  end

  object :questionnaire_user_answer do
    field(:uuid, non_null(:string))
    field(:question, :questionnaire_question)
    field(:answer, non_null(:string))
  end

  object :questionnaire do
    field(:uuid, non_null(:string))
    field(:name, non_null(:string))
    field(:description, :string)
    field(:questions, list_of(:questionnaire_question))
  end

  @desc ~s"""
  Input object for a questionnaire params
  """
  input_object :questionnaire_params_input_object do
    field(:name, non_null(:string))
    field(:description, :string)
    field(:ends_at, :datetime)
  end

  @desc ~s"""
  Input object for a questionnaire questions params
  """
  input_object :questionnaire_question_params_input_object do
    field(:question, non_null(:string))
    field(:type, non_null(:question_type))
    field(:order, :integer)
    field(:answer_options, :json)
    field(:has_extra_open_text_answer, :boolean, default_value: false)
  end

  @desc ~s"""
  Input object for a questionnaire answer params
  """
  input_object :questionnaire_answer_params_input_object do
    field(:answer, non_null(:json))
  end
end
