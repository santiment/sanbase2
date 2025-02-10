defmodule SanbaseWeb.Graphql.Schema.QuestionnaireQueries do
  @moduledoc ~s"""
  Queries and mutations for working with short urls
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Middlewares.JWTAuth
  alias SanbaseWeb.Graphql.Middlewares.JWTModeratorAuth
  alias SanbaseWeb.Graphql.Resolvers.QuestionnaireResolver

  object :questionnaire_queries do
    field :get_questionnaire, :questionnaire do
      meta(access: :free)
      arg(:questionnaire_uuid, non_null(:string))

      # middleware(JWTAuth)

      resolve(&QuestionnaireResolver.get_questionnaire/3)
    end

    field :get_questionnaire_user_answers, list_of(:questionnaire_user_answer) do
      meta(access: :free)
      arg(:questionnaire_uuid, non_null(:string))

      middleware(JWTAuth)

      resolve(&QuestionnaireResolver.get_questionnaire_user_answers/3)
    end
  end

  object :questionnaire_mutations do
    field :create_questionnaire, :questionnaire do
      arg(:params, :questionnaire_params_input_object)

      middleware(JWTModeratorAuth)

      resolve(&QuestionnaireResolver.create_questionnaire/3)
    end

    field :update_questionnaire, :questionnaire do
      arg(:questionnaire_uuid, non_null(:string))
      arg(:params, :questionnaire_params_input_object)

      middleware(JWTModeratorAuth)

      resolve(&QuestionnaireResolver.update_questionnaire/3)
    end

    field :delete_questionnaire, :questionnaire do
      arg(:questionnaire_uuid, non_null(:string))

      middleware(JWTModeratorAuth)

      resolve(&QuestionnaireResolver.delete_questionnaire/3)
    end

    field :create_questionnaire_question, :questionnaire do
      arg(:questionnaire_uuid, non_null(:string))

      arg(:params, :questionnaire_question_params_input_object)

      middleware(JWTModeratorAuth)

      resolve(&QuestionnaireResolver.create_question/3)
    end

    field :update_questionnaire_question, :questionnaire do
      arg(:question_uuid, non_null(:string))
      arg(:params, :questionnaire_question_params_input_object)

      middleware(JWTModeratorAuth)

      resolve(&QuestionnaireResolver.update_question/3)
    end

    field :delete_questionnaire_question, :questionnaire do
      arg(:question_uuid, non_null(:string))

      middleware(JWTModeratorAuth)

      resolve(&QuestionnaireResolver.delete_question/3)
    end

    field :create_questionnaire_answer, :questionnaire_answer do
      arg(:question_uuid, non_null(:string))
      arg(:params, :questionnaire_answer_params_input_object)

      middleware(JWTAuth)

      resolve(&QuestionnaireResolver.create_answer/3)
    end

    field :update_questionnaire_answer, :questionnaire_answer do
      arg(:answer_uuid, non_null(:string))
      arg(:params, :questionnaire_answer_params_input_object)

      middleware(JWTAuth)

      resolve(&QuestionnaireResolver.update_answer/3)
    end

    field :delete_questionnaire_answer, :questionnaire_answer do
      arg(:answer_uuid, non_null(:string))
      arg(:params, :questionnaire_answer_params_input_object)

      middleware(JWTAuth)

      resolve(&QuestionnaireResolver.delete_answer/3)
    end
  end
end
