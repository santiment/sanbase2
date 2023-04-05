defmodule Sanbase.Questionnaire.Validation do
  @moduledoc ~s"""
  Validation functions for the Questionnaire questions and answers
  """

  @doc ~s"""
  Validate the question listed answers' options list.

  Different question types have different validations.
    - The questions that have a custom set of answer options have the most
    exhausive validations.
    - The open questions not have any validations as they don't specify a list
    of possible answers
    - The boolean question type has validation that forces it to have two answers,
    the first one being `true` and the second one being `false`, in that order.
    This is for consistency. It can be done as a `single_select` type, but the answers
    and casing can vary between questions.
  """
  @spec validate_question_answers_options(Atom.t(), map) ::
          true | {:error, String.t()}
  def validate_question_answers_options(type, answers_map)
      when type in [:single_select, :multiple_select] do
    with true <- answers_are_map?(answers_map),
         true <- has_more_than_one_answer?(answers_map),
         true <- all_keys_are_integers?(answers_map),
         true <- all_keys_are_sequential?(answers_map),
         true <- all_values_are_not_empty?(answers_map),
         true <- all_values_are_different?(answers_map) do
      true
    end
  end

  def validate_question_answers_options(type, _answers_map)
      when type in [:open_text, :open_number] do
    true
  end

  def validate_question_answers_options(:boolean, answers_map) do
    # Enforce that the boolean question answers option always have the same format
    # This will allow for easy
    case %{"1" => "true", "2" => "false"} == answers_map do
      true ->
        true

      false ->
        {:error, ~s|The boolean answers option must be a map: {"1": "true", "2" => "false"|}
    end
  end

  @doc ~s"""
  Check the that question is non-empty string with at least 4 characters
  """
  @spec validate_question_text(Atom.t(), String.t()) ::
          true | {:error, String.t()}
  def validate_question_text(_type, question) do
    case is_binary(question) and String.length(String.trim(question)) >= 4 do
      true ->
        true

      false ->
        {:error, "The question must be a string with at least 4 characters"}
    end
  end

  def validate_user_provided_answer(answer, type)
      when type in [:single_select, :multiple_select] do
    cond do
      Map.has_key?(answer, "open_text_answer") and
          is_binary(answer["open_text_answer"]) ->
        true

      Map.has_key?(answer, "open_number_answer") and
          is_number(answer["open_number_answer"]) ->
        true

      Map.has_key?(answer, "answer_selection") and type == :single_select ->
        case answer["answer_selection"] |> Integer.parse() do
          {_, ""} ->
            true

          _ ->
            {:error,
             "If the answer is a single selection of given options, it must be a number represented as string"}
        end

      Map.has_key?(answer, "answer_selection") and type == :multiple_select ->
        is_integer = fn val -> match?({_, ""}, Integer.parse(val)) end

        case Enum.all?(answer["answer_selection"], is_integer) do
          true ->
            true

          false ->
            {:error,
             "If the answer is a multi selection of given options, it must be a list of numbers represented as strings"}
        end

      true ->
        {:error,
         """
         Invalid answer format. It must be a map with key 'open_text_answer', \
         'open_number_answer' or 'answer_selection'
         """}
    end
  end

  def validate_user_provided_answer(answer, :open_text) do
    case Map.has_key?(answer, "open_text_answer") and
           is_binary(answer["open_text_answer"]) do
      true ->
        true

      false ->
        {:error,
         "The 'open_text' question type answer must be a map with key 'open_text_answer' and string value."}
    end
  end

  def validate_user_provided_answer(answer, :open_number) do
    case Map.has_key?(answer, "open_number_answer") and
           is_binary(answer["open_number_answer"]) do
      true ->
        true

      false ->
        {:error,
         "The 'open_number' question type answer must be a map with key 'open_number_answer' and number value."}
    end
  end

  def validate_user_provided_answer(answer, :boolean) do
    case Map.has_key?(answer, "answer_selection") and
           answer["answer_selection"] in ["1", "2"] do
      true ->
        true

      false ->
        {:error,
         "The 'boolean' question type answer must be a map with key 'answer_selection' and string value."}
    end
  end

  # Private functions

  defp answers_are_map?(answers) do
    case answers do
      %{} ->
        true

      _ ->
        {:error,
         "The answers must be a map with sequential integers as keys and strings as values"}
    end
  end

  defp has_more_than_one_answer?(%{} = answers_map) do
    case map_size(answers_map) do
      value when value >= 2 ->
        true

      _ ->
        {:error, "Questions with select options must have at least 2 answer choices."}
    end
  end

  defp all_keys_are_integers?(answers_map) do
    keys = Map.keys(answers_map)

    Enum.reduce_while(keys, true, fn key, _acc ->
      case Integer.parse(key) do
        {_num, ""} ->
          {:cont, true}

        _ ->
          {:halt, {:error, "The key of the answer is not a number. Got #{inspect(key)}"}}
      end
    end)
  end

  defp all_keys_are_sequential?(answers_map) do
    keys = answers_map |> Map.keys() |> Enum.map(&String.to_integer/1)

    # Break if the answer options are not integers from 1 to N
    case Enum.sort(keys) == Enum.to_list(1..length(keys)) do
      true -> true
      false -> {:error, "The answers keys are not numbers from 1 to N"}
    end
  end

  defp all_values_are_not_empty?(answers_map) do
    Enum.reduce_while(answers_map, true, fn {_key, value}, _acc ->
      cond do
        not is_binary(value) ->
          {:halt, {:error, "All answers must be strings"}}

        String.trim(value) == "" ->
          {:halt, {:error, "All answers must be non-empty strings"}}

        true ->
          {:cont, true}
      end
    end)
  end

  defp all_values_are_different?(answers_map) do
    values = Map.values(answers_map)

    case values == Enum.uniq(values) do
      true -> true
      false -> {:error, "All of the question's answers must be different"}
    end
  end
end
