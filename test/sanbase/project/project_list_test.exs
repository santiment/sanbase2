defmodule Sanbase.Model.ProjectListTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Model.Project

  import Sanbase.Factory

  test "all projects" do
    assert Project.List.projects() == []
  end

  test "all erc20 projects" do
    assert Project.List.erc20_projects() == []
  end

  test "all currency projects" do
    assert Project.List.currency_projects() == []
  end

  test "projects with min_volume above 1000" do
    assert Project.List.projects(min_volume: 1000) == []
  end

  test "without hidden projects" do
    assert Project.List.projects(show_hidden_projects?: false) == []
  end

  test "with hidden projects" do
    assert Project.List.projects(show_hidden_projects?: true) == []
  end

  test "all projects page" do
    assert Project.List.projects_page(1, 10) == []
  end

  test "all erc20 projects page" do
    assert Project.List.erc20_projects_page(1, 10) == []
  end

  test "all currency projects page" do
    assert Project.List.currency_projects_page(1, 10) == []
  end

  test "with source" do
    assert Project.List.projects_with_source("coinmarketcap") == []
  end
end
