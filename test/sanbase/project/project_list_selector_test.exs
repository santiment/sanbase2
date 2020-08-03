defmodule Sanbase.Model.ProjectListSelectorTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Model.Project.ListSelector

  test "filters must be a list of maps" do
    selector = %{
      filters: [
        metric: "nvt",
        from_dynamic: "1d",
        to_dynamic: "now",
        aggregation: :last,
        operation: :greater_than,
        threshold: 10
      ]
    }

    {:error, error_msg} = ListSelector.valid_selector?(%{selector: selector})
    assert error_msg =~ "must be a map"
  end

  test "invalid metric is caught" do
    selector = %{
      filters: [
        %{
          metric: "nvtt",
          from_dynamic: "1d",
          to_dynamic: "now",
          aggregation: :last,
          operation: :greater_than,
          threshold: 10
        }
      ]
    }

    {:error, error_msg} = ListSelector.valid_selector?(%{selector: selector})
    assert error_msg =~ "The metric 'nvtt' is not supported or is mistyped. Did you mean 'nvt'?"
  end
end
