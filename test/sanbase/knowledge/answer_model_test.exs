defmodule Sanbase.Knowledge.AnswerModelTest do
  use ExUnit.Case, async: true

  alias Sanbase.Knowledge.AnswerModel

  defp openrouter_key_set?() do
    case System.get_env("OPENROUTER_API_KEY") do
      v when is_binary(v) and v != "" -> true
      _ -> false
    end
  end

  describe "selectable/0" do
    test "always offers the OpenAI gpt models" do
      keys = Enum.map(AnswerModel.selectable(), & &1.key)
      assert "gpt-5-nano" in keys
      assert "gpt-5-mini" in keys
    end

    test "offers the OpenRouter model only when OPENROUTER_API_KEY is set" do
      keys = Enum.map(AnswerModel.selectable(), & &1.key)
      assert "deepseek-v4-flash" in keys == openrouter_key_set?()
    end
  end

  describe "default_key/0" do
    test "is the first available entry (always present gpt-5-nano)" do
      assert AnswerModel.default_key() == "gpt-5-nano"
    end
  end

  describe "options_for/1" do
    test "maps a known key to its client and model" do
      assert AnswerModel.options_for("gpt-5-mini") == [
               answer_client: Sanbase.OpenAI.Question,
               answer_model: "gpt-5-mini"
             ]
    end

    test "returns [] for an unknown key (falls back to default)" do
      assert AnswerModel.options_for("nope") == []
      assert AnswerModel.options_for(nil) == []
    end
  end

  describe "client/1 and resolve/1" do
    test "client/1 honours an explicit :answer_client" do
      assert AnswerModel.client(answer_client: Sanbase.OpenRouter.Question) ==
               Sanbase.OpenRouter.Question
    end

    test "resolve/1 honours an explicit :answer_model" do
      assert AnswerModel.resolve(answer_model: "some/model") == "some/model"
    end

    test "resolve/1 falls back to the client's default model" do
      assert AnswerModel.resolve(answer_client: Sanbase.OpenAI.Question) ==
               Sanbase.OpenAI.Question.default_model()
    end
  end
end
