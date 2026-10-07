defmodule Sanbase.AI.OpenAITracingTest do
  use ExUnit.Case, async: true

  alias Sanbase.OpenAI.Traced
  alias Sanbase.OpenAI.Tracing

  describe "usage_details/1" do
    test "splits cached input and reasoning output into their own keys" do
      usage = %{
        "prompt_tokens" => 1000,
        "completion_tokens" => 300,
        "total_tokens" => 1300,
        "prompt_tokens_details" => %{"cached_tokens" => 400, "audio_tokens" => nil},
        "completion_tokens_details" => %{"reasoning_tokens" => 120}
      }

      assert Tracing.usage_details(usage) == %{
               "input" => 600,
               "input_cached_tokens" => 400,
               "output" => 180,
               "output_reasoning_tokens" => 120,
               "total" => 1300
             }
    end

    test "works without the details objects" do
      assert %{"input" => 10, "output" => 5, "total" => 15} =
               Tracing.usage_details(%{"prompt_tokens" => 10, "completion_tokens" => 5})
    end

    test "returns nil when there is no usage" do
      assert Tracing.usage_details(nil) == nil
      assert Tracing.usage_details(%{}) == nil
    end
  end

  describe "result normalization" do
    test "callers get the content back from a completion map" do
      completion = {:ok, %{content: "answer", model: "m", usage: %{"prompt_tokens" => 1}}}

      assert {:ok, %{content: "answer", model: "m", usage: %{}}} =
               normalized = Traced.normalize_result(completion)

      assert Traced.unwrap_result(normalized) == {:ok, "answer"}
    end

    test "plain content and errors pass through" do
      assert {:ok, "answer"} =
               {:ok, "answer"} |> Traced.normalize_result() |> Traced.unwrap_result()

      assert {:error, :boom} =
               {:error, :boom} |> Traced.normalize_result() |> Traced.unwrap_result()
    end
  end

  test "reasoning effort is recorded as a model parameter" do
    assert %{model_parameters: %{reasoning_effort: "low"}} =
             Traced.maybe_add_model_parameters(%{reasoning_effort: "low"})

    assert Traced.maybe_add_model_parameters(%{model: "m"}) == %{model: "m"}
  end
end
