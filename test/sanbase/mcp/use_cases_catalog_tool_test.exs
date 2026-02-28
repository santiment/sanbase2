defmodule Sanbase.MCP.UseCasesCatalogToolTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.MCP.UseCasesCatalog

  describe "UseCasesCatalog" do
    test "returns all use cases with required fields" do
      use_cases = UseCasesCatalog.all_use_cases()

      assert is_list(use_cases)
      assert length(use_cases) > 0

      Enum.each(use_cases, fn use_case ->
        assert use_case.title
        assert is_binary(use_case.steps)
        assert String.length(use_case.steps) > 100
        assert use_case.interpretation
        assert String.contains?(use_case.steps, "Step 1")
      end)
    end

    test "steps mention tools to use" do
      use_cases = UseCasesCatalog.all_use_cases()

      Enum.each(use_cases, fn use_case ->
        assert String.contains?(use_case.steps, "tool") or
                 String.contains?(use_case.steps, "fetch_metric_data")
      end)
    end
  end

  describe "UseCasesCatalogTool execute/2" do
    test "returns simplified list of use cases" do
      frame = %{assigns: %{}}

      {:reply, response, _frame} = Sanbase.MCP.UseCasesCatalogTool.execute(%{}, frame)

      assert response.content
      [%{"text" => json_text, "type" => "text"}] = response.content
      use_cases = Jason.decode!(json_text)

      assert is_list(use_cases)
      assert length(use_cases) > 0
    end

    test "returned use cases have only title, steps, and interpretation" do
      frame = %{assigns: %{}}

      {:reply, response, _frame} = Sanbase.MCP.UseCasesCatalogTool.execute(%{}, frame)

      [%{"text" => json_text, "type" => "text"}] = response.content
      use_cases = Jason.decode!(json_text)
      use_case = List.first(use_cases)

      assert use_case["title"]
      assert use_case["steps"]
      assert use_case["interpretation"]

      assert is_binary(use_case["steps"])
      assert String.length(use_case["steps"]) > 100

      refute Map.has_key?(use_case, "id")
      refute Map.has_key?(use_case, "description")
      refute Map.has_key?(use_case, "category")
      refute Map.has_key?(use_case, "metadata")
    end

    test "steps is plain text not a list" do
      frame = %{assigns: %{}}

      {:reply, response, _frame} = Sanbase.MCP.UseCasesCatalogTool.execute(%{}, frame)

      [%{"text" => json_text, "type" => "text"}] = response.content
      use_cases = Jason.decode!(json_text)

      Enum.each(use_cases, fn use_case ->
        assert is_binary(use_case["steps"])
        refute is_list(use_case["steps"])
      end)
    end
  end
end
