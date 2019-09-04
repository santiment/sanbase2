defmodule Sanbase.Signal.ValidationTest do
  use Sanbase.DataCase, async: true

  alias Sanbase.Signal.Validation

  describe "#load_in_struct" do
    alias Sanbase.Signal.StructMapTransformation
    alias Sanbase.Signal.UserTrigger

    test "not supported keys in settings return error" do
      # mistyped `time_window` as `time_windo`
      settings = %{
        "type" => "price_percent_change",
        "target" => %{"slug" => "santiment"},
        "channel" => "telegram",
        "time_windo" => "24h",
        "operation" => %{"above" => 5}
      }

      assert StructMapTransformation.load_in_struct_if_valid(settings) ==
               {:error, ~s/The trigger contains unsupported or mistyped field "time_windo"/}
    end

    # The historical activity API accepts JSON string as settings. The string keys
    # are converted to atoms if they exist.
    test "historical activity fails" do
      # `operation` is mistyped as `operatio`
      trigger = %{
        cooldown: "4h",
        settings: %{
          "type" => "price_percent_change",
          "target" => %{"slug" => "santiment"},
          "channel" => "telegram",
          "time_window" => "4h",
          "operatio" => %{"percent_up" => 5.0}
        }
      }

      assert UserTrigger.historical_trigger_points(trigger) ==
               {:error, ~s/The trigger contains unsupported or mistyped field "operatio"/}
    end
  end

  describe "#valid_absolute_value_operation?" do
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
        |> Enum.all?(fn operation ->
          Validation.valid_operation?(operation) == :ok
        end)

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
          Validation.valid_operation?(operation) |> elem(0) == :error
        end)

      assert all_errors?
    end
  end

  describe "#valid_percent_change_operation?" do
    test "with valid cases returns :ok" do
      valid_cases = [
        %{percent_up: 10},
        %{percent_up: 10.5},
        %{percent_down: 20}
      ]

      all_true? =
        valid_cases
        |> Enum.all?(fn operation ->
          Validation.valid_operation?(operation) == :ok
        end)

      assert all_true?
    end

    test "with all_of valid cases returns :ok" do
      valid_cases = [
        %{percent_up: 10},
        %{percent_up: 10.5},
        %{percent_down: 20}
      ]

      assert Validation.valid_operation?(%{all_of: valid_cases}) == :ok
    end

    test "with some_of valid cases returns :ok" do
      valid_cases = [
        %{percent_up: 10},
        %{percent_up: 10.5},
        %{percent_down: 20}
      ]

      assert Validation.valid_operation?(%{some_of: valid_cases}) == :ok
    end

    test "with different operations in all_of returns proper error message" do
      valid_cases = [
        %{above: 10},
        %{percent_up: 10.5},
        %{percent_down: 20}
      ]

      assert Validation.valid_operation?(%{all_of: valid_cases}) ==
               {:error, "Some of the operations are not valid"}
    end

    test "with different operations in some_of returns proper error message" do
      valid_cases = [
        %{above: 10},
        %{percent_up: 10.5},
        %{percent_down: 20}
      ]

      assert Validation.valid_operation?(%{some_of: valid_cases}) ==
               {:error, "Some of the operations are not valid"}
    end

    test "with invalid parameters in some_of returns proper error message" do
      valid_cases = [
        %{percent_up: 10},
        %{percent_up: "NaN"},
        %{percent_down: "5"}
      ]

      assert Validation.valid_operation?(%{some_of: valid_cases}) ==
               {:error, "Some of the operations are not valid"}
    end

    test "with invalid parameters in all_of returns proper error message" do
      valid_cases = [
        %{percent_up: 10},
        %{percent_up: "NaN"},
        %{percent_down: "5"}
      ]

      assert Validation.valid_operation?(%{all_of: valid_cases}) ==
               {:error, "Some of the operations are not valid"}
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
          Validation.valid_operation?(operation) |> elem(0) == :error
        end)

      assert all_errors?
    end
  end
end
