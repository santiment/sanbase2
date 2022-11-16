defmodule SanbaseWeb.DataControllerTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory

  require Sanbase.Utils.Config, as: Config

  setup do
    p1 = insert(:random_erc20_project)
    p2 = insert(:random_erc20_project)
    p3 = insert(:random_erc20_project)

    secret = Config.module_get(Sanbase.RepoReader, :projects_data_endpoint_secret)
    {:ok, path} = Temp.mkdir("projects_data")
    on_exit(fn -> File.rm_rf!(path) end)
    %{p1: p1, p2: p2, p3: p3, path: path, secret: secret}
  end

  test "validator webhook - correct", context do
    Sanbase.Mock.prepare_mock(Sanbase.RepoReader.Utils, :clone_repo, fn _, _ ->
      clone_repo_mock(context.path, Path.join(__DIR__, "data_correct.json"))
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      context.conn
      |> post("/projects_data_validator_webhook/#{context.secret}", %{
        "branch" => "some_branch",
        "changed_files" => "projects/santiment/data.json"
      })
      |> json_response(200)
    end)
  end

  @tag capture_log: true
  test "validator webhook - missing slug", context do
    Sanbase.Mock.prepare_mock(Sanbase.RepoReader.Utils, :clone_repo, fn _, _ ->
      clone_repo_mock(context.path, Path.join(__DIR__, "data_missing_slug.json"))
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert %{"error" => error} =
               context.conn
               |> post("/projects_data_validator_webhook/#{context.secret}", %{
                 "branch" => "some_branch",
                 "changed_files" => "projects/santiment/data.json"
               })
               |> json_response(400)

      assert error =~ "in directory santiment"
      assert error =~ "No slug found or it is not a string"
    end)
  end

  test "validator webhook - wrong decimals type", context do
    Sanbase.Mock.prepare_mock(Sanbase.RepoReader.Utils, :clone_repo, fn _, _ ->
      clone_repo_mock(context.path, Path.join(__DIR__, "data_wrong_type.json"))
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert %{"error" => error} =
               context.conn
               |> post("/projects_data_validator_webhook/#{context.secret}", %{
                 "branch" => "some_branch",
                 "changed_files" => "projects/santiment/data.json"
               })
               |> json_response(400)

      assert error =~ "Type mismatch. Expected Integer but got String"
      assert error =~ "#/blockchain/contracts/0/decimals"
    end)
  end

  test "validator webhook - invalid url", context do
    Sanbase.Mock.prepare_mock(Sanbase.RepoReader.Utils, :clone_repo, fn _, _ ->
      clone_repo_mock(context.path, Path.join(__DIR__, "data_invalid_url.json"))
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert %{"error" => error} =
               context.conn
               |> post("/projects_data_validator_webhook/#{context.secret}", %{
                 "branch" => "some_branch",
                 "changed_files" => "projects/santiment/data.json"
               })
               |> json_response(400)

      assert error =~ "The discord URL discord.com/santiment is invalid"
    end)
  end

  defp clone_repo_mock(destination, source_file) do
    path = Path.join([destination, "projects", "santiment"])
    File.mkdir_p!(path)
    File.cp!(source_file, Path.join([path, "data.json"]))

    repo = %Sanbase.RepoReader.Repository{path: destination}
    {:ok, repo}
  end
end
