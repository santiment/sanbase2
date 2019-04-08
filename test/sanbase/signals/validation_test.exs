defmodule Sanbase.Signals.ValidationTest do
  use Sanbase.DataCase, async: true

  alias Sanbase.Signals.Validation

  describe "#valid_operation?" do
    test "with valid cases returns :ok" do
      valid_cases = [
        %{above: 10},
        %{above: 10.5},
        %{below: 20},
        %{inside_channel: [10, 20]},
        %{outside_channel: [10, 20]}
      ]

      all_true? =
        valid_cases
        |> Enum.all?(fn operation -> Validation.valid_operation?(operation) == :ok end)

      assert all_true?
    end

    test "with invalid cases returns {:error, error_message}" do
      error_cases = [
        %{above: "10"},
        %{"below" => 20},
        %{inside_channel: [20, 10]},
        %{inside_channel: [10, 20, 30]},
        %{inside_channel: ["10", "20"]},
        %{outside_channel: [10, 10]},
        %{non_existing: 10}
      ]

      all_errors? =
        error_cases
        |> Enum.all?(fn operation ->
          Validation.valid_operation?(operation) ==
            {:error, "#{inspect(operation)} is not a valid operation"}
        end)

      assert all_errors?
    end
  end

  describe "#valid_percent_operation?" do
    test "with valid cases returns :ok" do
      valid_cases = [
        %{percent_up: 10},
        %{percent_up: 10.5},
        %{percent_down: 20}
      ]

      all_true? =
        valid_cases
        |> Enum.all?(fn operation -> Validation.valid_percent_operation?(operation) == :ok end)

      assert all_true?
    end

    test "with invalid cases returns {:error, error_message}" do
      error_cases = [
        %{percent_up: "10"},
        %{"percent_down" => 20},
        %{non_existing: 10},
        %{percent_up: 0},
        %{percent_up: -10}
      ]

      all_errors? =
        error_cases
        |> Enum.all?(fn operation ->
          Validation.valid_percent_operation?(operation) ==
            {:error, "#{inspect(operation)} is not a valid percent operation"}
        end)

      assert all_errors?
    end
  end
end
