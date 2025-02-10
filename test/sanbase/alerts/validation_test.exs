defmodule Sanbase.Alert.ValidationTest do
  use Sanbase.DataCase, async: true

  alias Sanbase.Alert.Validation

  describe "#load_in_struct" do
    alias Sanbase.Alert.StructMapTransformation
    alias Sanbase.Alert.UserTrigger

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

  describe "#valid_operation? for absolute value operations" do
    test "with valid cases returns :ok" do
      valid_cases = [
        %{above: 10},
        %{above: 10.5},
        %{below: 20},
        %{inside_channel: [10, 20]},
        %{outside_channel: [10, 20]}
      ]

      all_true? =
        Enum.all?(valid_cases, fn operation ->
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
        Enum.all?(error_cases, fn operation ->
          operation |> Validation.valid_operation?() |> elem(0) == :error
        end)

      assert all_errors?
    end
  end

  describe "#valid_operation? for percent change operations" do
    test "with valid cases returns :ok" do
      valid_cases = [
        %{percent_up: 10},
        %{percent_up: 10.5},
        %{percent_down: 20}
      ]

      all_true? =
        Enum.all?(valid_cases, fn operation ->
          Validation.valid_percent_change_operation?(operation) == :ok
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
               {:error, "Not all operations are from the same type"}
    end

    test "with different operations in some_of returns proper error message" do
      valid_cases = [
        %{above: 10},
        %{percent_up: 10.5},
        %{percent_down: 20}
      ]

      assert Validation.valid_operation?(%{some_of: valid_cases}) ==
               {:error, "Not all operations are from the same type"}
    end

    test "with invalid parameters in some_of returns proper error message" do
      valid_cases = [
        %{percent_up: 10},
        %{percent_up: "NaN"},
        %{percent_down: "5"}
      ]

      assert Validation.valid_operation?(%{some_of: valid_cases}) ==
               {:error, "The list of operation contains not valid operation: %{percent_up: \"NaN\"}"}
    end

    test "with invalid parameters in all_of returns proper error message" do
      valid_cases = [
        %{percent_up: 10},
        %{percent_up: "NaN"},
        %{percent_down: "5"}
      ]

      assert Validation.valid_operation?(%{all_of: valid_cases}) ==
               {:error, "The list of operation contains not valid operation: %{percent_up: \"NaN\"}"}
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
        Enum.all?(error_cases, fn operation ->
          operation |> Validation.valid_operation?() |> elem(0) == :error
        end)

      assert all_errors?
    end
  end

  describe "#valid_absolute_change_operation?" do
    test "with valid cases returns :ok" do
      valid_cases = [
        %{amount_up: 10},
        %{amount_up: 10.5},
        %{amount_down: 20},
        %{inside_channel: [10, 20]},
        %{outside_channel: [10, 20]}
      ]

      all_true? =
        Enum.all?(valid_cases, fn operation ->
          Validation.valid_absolute_change_operation?(operation) == :ok
        end)

      assert all_true?
    end

    test "with invalid cases returns {:error, error_message}" do
      error_cases = [
        %{amount_up: "10"},
        %{"amount_down" => 20},
        %{inside_channel: [20, 10]},
        %{inside_channel: [10, 20, 30]},
        %{inside_channel: ["10", "20"]},
        %{outside_channel: [10, 10]},
        %{non_existing: 10}
      ]

      all_errors? =
        Enum.all?(error_cases, fn operation ->
          operation |> Validation.valid_absolute_change_operation?() |> elem(0) == :error
        end)

      assert all_errors?
    end

    test "with invalid as a whole operation returns proper error message" do
      assert Validation.valid_absolute_change_operation?(%{amount_up: "10"}) ==
               {:error, "%{amount_up: \"10\"} is not a valid operation"}
    end

    test "with invalid operation, because it is a percent one, returns proper error message" do
      assert Validation.valid_absolute_change_operation?(%{percent_up: 10}) ==
               {:error, "%{percent_up: 10} is a percent, not an absolute change one."}
    end

    test "with invalid operation, because it is a absolute value one, returns proper error message" do
      assert Validation.valid_absolute_change_operation?(%{above: 10}) ==
               {:error, "%{above: 10} is an absolute value operation, not an absolute change one."}
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
        Enum.all?(valid_cases, fn operation ->
          Validation.valid_absolute_value_operation?(operation) == :ok
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
        Enum.all?(error_cases, fn operation ->
          operation |> Validation.valid_absolute_value_operation?() |> elem(0) == :error
        end)

      assert all_errors?
    end

    test "with invalid as a whole operation returns proper error message" do
      assert Validation.valid_absolute_value_operation?(%{above: "10"}) ==
               {:error, "%{above: \"10\"} is not a valid operation"}
    end

    test "with invalid operation, because it is a percent one, returns proper error message" do
      assert Validation.valid_absolute_value_operation?(%{percent_up: 10}) ==
               {:error, "%{percent_up: 10} is a percent, not an absolute value one."}
    end

    test "with invalid operation, because it is a absolute change one, returns proper error message" do
      assert Validation.valid_absolute_value_operation?(%{amount_up: 10}) ==
               {:error, "%{amount_up: 10} is an absolute change operation, not an absolute value one."}
    end
  end

  describe "#valid_percent_change_operation?" do
    test "with valid cases returns :ok" do
      valid_cases = [
        %{percent_up: 10},
        %{percent_down: 10.5},
        %{percent_down: 20},
        %{inside_channel: [10, 20]},
        %{outside_channel: [10, 20]}
      ]

      all_true? =
        Enum.all?(valid_cases, fn operation ->
          Validation.valid_percent_change_operation?(operation) == :ok
        end)

      assert all_true?
    end

    test "with invalid cases returns {:error, error_message}" do
      error_cases = [
        %{percent_up: "10"},
        %{"percent_up" => 20},
        %{inside_channel: [20, 10]},
        %{inside_channel: [10, 20, 30]},
        %{inside_channel: ["10", "20"]},
        %{outside_channel: [10, 10]},
        %{non_existing: 10}
      ]

      all_errors? =
        Enum.all?(error_cases, fn operation ->
          operation |> Validation.valid_percent_change_operation?() |> elem(0) == :error
        end)

      assert all_errors?
    end

    test "with invalid as a whole operation returns proper error message}" do
      assert Validation.valid_percent_change_operation?(%{percent_up: "10"}) ==
               {:error, "%{percent_up: \"10\"} is not a valid operation"}
    end

    test "with invalid operation, because it is an absolute value one, returns proper error message" do
      assert Validation.valid_percent_change_operation?(%{above: 10}) ==
               {:error, "%{above: 10} is an absolute operation, not a percent change one."}
    end

    test "with invalid operation, because it is a absolute change one, returns proper error message" do
      assert Validation.valid_percent_change_operation?(%{amount_up: 10}) ==
               {:error, "%{amount_up: 10} is an absolute operation, not a percent change one."}
    end
  end

  describe "#combinator operations?" do
    test "with valid cases in some_of returns :ok" do
      valid_case = %{
        some_of: [
          %{percent_up: 10},
          %{percent_down: 10.5},
          %{percent_down: 20}
        ]
      }

      assert Validation.valid_percent_change_operation?(valid_case) == :ok
    end

    test "with valid cases in all_of returns :ok" do
      valid_case = %{
        all_of: [
          %{percent_up: 10},
          %{percent_down: 10.5},
          %{percent_down: 20}
        ]
      }

      assert Validation.valid_percent_change_operation?(valid_case) == :ok
    end

    test "with valid cases in none_of returns :ok" do
      valid_case = %{
        none_of: [
          %{percent_up: 10},
          %{percent_down: 10.5},
          %{percent_down: 20}
        ]
      }

      assert Validation.valid_percent_change_operation?(valid_case) == :ok
    end

    test "with invalid cases returns {:error, error_message}" do
      error_case = %{
        some_of: [
          %{percent_up: "10"},
          %{"percent_up" => 20},
          %{inside_channel: [20, 10]},
          %{inside_channel: [10, 20, 30]},
          %{inside_channel: ["10", "20"]},
          %{outside_channel: [10, 10]},
          %{non_existing: 10}
        ]
      }

      assert error_case |> Validation.valid_percent_change_operation?() |> elem(0) == :error
    end

    test "with a not fitting operation in a percent some_of returns proper message" do
      assert Validation.valid_percent_change_operation?(%{
               some_of: [%{percent_up: 10}, %{above: 10}]
             }) ==
               {:error, "Not all operations are from the same type"}
    end

    test "with invalid operation in a some_of returns proper message" do
      assert Validation.valid_percent_change_operation?(%{
               some_of: [%{percent_up: 10}, %{above: "10"}]
             }) ==
               {:error, "The list of operation contains not valid operation: %{above: \"10\"}"}
    end

    test "with a not fitting operation in an absolute change some_of, because all must be absolute change ones, returns proper message" do
      assert Validation.valid_absolute_change_operation?(%{
               some_of: [%{amount_up: 10}, %{above: 10}]
             }) ==
               {:error, "Not all operations are from the same type"}
    end

    test "with a not fitting operation in an absolute value some_of, because all must be absolute value ones, returns proper message" do
      assert Validation.valid_absolute_change_operation?(%{
               some_of: [%{above: 10}, %{amount_down: 10}]
             }) ==
               {:error, "Not all operations are from the same type"}
    end

    test "with a not fitting operation in a percent all_of returns proper message" do
      assert Validation.valid_percent_change_operation?(%{
               all_of: [%{percent_up: 10}, %{above: 10}]
             }) ==
               {:error, "Not all operations are from the same type"}
    end

    test "with a not fitting operation in an absolute change all_of, because all must be absolute change ones, returns proper message" do
      assert Validation.valid_absolute_change_operation?(%{
               all_of: [%{amount_up: 10}, %{above: 10}]
             }) ==
               {:error, "Not all operations are from the same type"}
    end

    test "with a not fitting operation in an absolute value all_of, because all must be absolute value ones, returns proper message" do
      assert Validation.valid_absolute_change_operation?(%{
               all_of: [%{above: 10}, %{amount_down: 10}]
             }) ==
               {:error, "Not all operations are from the same type"}
    end

    test "with a not fitting operation in a percent none_of returns proper message" do
      assert Validation.valid_percent_change_operation?(%{
               none_of: [%{percent_up: 10}, %{above: 10}]
             }) ==
               {:error, "Not all operations are from the same type"}
    end

    test "with a not fitting operation in an absolute change none_of, because all must be absolute change ones, returns proper message" do
      assert Validation.valid_absolute_change_operation?(%{
               none_of: [%{amount_up: 10}, %{above: 10}]
             }) ==
               {:error, "Not all operations are from the same type"}
    end

    test "with a not fitting operation in an absolute value none_of, because all must be absolute value ones, returns proper message" do
      assert Validation.valid_absolute_change_operation?(%{
               none_of: [%{above: 10}, %{amount_down: 10}]
             }) ==
               {:error, "Not all operations are from the same type"}
    end
  end

  describe "#valid_slug?" do
    test "with binary slug, which is a project, returns :ok" do
      project = Sanbase.Factory.insert(:random_project)
      assert Validation.valid_slug?(%{slug: project.slug}) == :ok
    end

    test "with binary slug, but not a project, returns :error" do
      slug = %{slug: "something incorrect"}

      assert Validation.valid_slug?(slug) ==
               {:error, "\"something incorrect\" is not a valid slug"}
    end

    test "with argument not a binary slug, returns :error" do
      argument = "incorrect argument"

      assert Validation.valid_slug?(argument) ==
               {:error,
                "\"incorrect argument\" is not a valid slug. A valid slug is a map with a single slug key and string value"}
    end
  end
end
