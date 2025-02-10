defmodule SanbaseWeb.RepoReaderControllerTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.RepoReader.Utils

  require Sanbase.Utils.Config, as: Config

  setup do
    secret = Config.module_get(Sanbase.RepoReader, :projects_data_endpoint_secret)
    {:ok, path} = Temp.mkdir("projects_data")
    on_exit(fn -> File.rm_rf!(path) end)
    %{path: path, secret: secret}
  end

  describe "validation" do
    test "validator webhook with exception", context do
      Utils
      |> Sanbase.Mock.prepare_mock(:clone_repo, fn _, _ ->
        raise("Some exception")
      end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert %{"error" => error} =
                 context.conn
                 |> post("/projects_data_validator_webhook", %{
                   "fork_repo" => "not_santiment/projects",
                   "branch" => "some_branch",
                   "changed_files" => "projects/santiment/data.json"
                 })
                 |> json_response(400)

        assert error =~ "Some exception"
      end)
    end

    test "validator webhook with match error", context do
      Utils
      |> Sanbase.Mock.prepare_mock(:clone_repo, fn _, _ ->
        {:error, "Some unexpected error"}
      end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert %{"error" => error} =
                 context.conn
                 |> post("/projects_data_validator_webhook", %{
                   "fork_repo" => "not_santiment/projects",
                   "branch" => "some_branch",
                   "changed_files" => "projects/santiment/data.json"
                 })
                 |> json_response(400)

        assert error =~ "Some unexpected error"
      end)
    end

    test "validator webhook - correct", context do
      Utils
      |> Sanbase.Mock.prepare_mock(:clone_repo, fn _, _ ->
        clone_repo_mock(context.path, Path.join(__DIR__, "data_correct.json"))
      end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        context.conn
        |> post("/projects_data_validator_webhook", %{
          "fork_repo" => "not_santiment/projects",
          "branch" => "some_branch",
          "changed_files" => "projects/santiment/data.json"
        })
        |> json_response(200)
      end)
    end

    @tag capture_log: true
    test "validator webhook - missing slug", context do
      Utils
      |> Sanbase.Mock.prepare_mock(:clone_repo, fn _, _ ->
        clone_repo_mock(context.path, Path.join(__DIR__, "data_missing_slug.json"))
      end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert %{"error" => error} =
                 context.conn
                 |> post("/projects_data_validator_webhook", %{
                   "fork_repo" => "not_santiment/projects",
                   "branch" => "some_branch",
                   "changed_files" => "projects/santiment/data.json"
                 })
                 |> json_response(400)

        assert error =~ "in directory santiment"
        assert error =~ "No slug found or it is not a string"
      end)
    end

    test "validator webhook - wrong decimals type", context do
      Utils
      |> Sanbase.Mock.prepare_mock(:clone_repo, fn _, _ ->
        clone_repo_mock(context.path, Path.join(__DIR__, "data_wrong_type.json"))
      end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert %{"error" => error} =
                 context.conn
                 |> post("/projects_data_validator_webhook", %{
                   "fork_repo" => "not_santiment/projects",
                   "branch" => "some_branch",
                   "changed_files" => "projects/santiment/data.json"
                 })
                 |> json_response(400)

        assert error =~ "Type mismatch. Expected Integer but got String"
        assert error =~ "#/blockchain/contracts/0/decimals"
      end)
    end

    test "validator webhook - invalid url", context do
      Utils
      |> Sanbase.Mock.prepare_mock(:clone_repo, fn _, _ ->
        clone_repo_mock(context.path, Path.join(__DIR__, "data_invalid_url.json"))
      end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert %{"error" => error} =
                 context.conn
                 |> post("/projects_data_validator_webhook", %{
                   "fork_repo" => "not_santiment/projects",
                   "branch" => "some_branch",
                   "changed_files" => "projects/santiment/data.json"
                 })
                 |> json_response(400)

        assert error =~ "The discord URL discord.com/santiment is invalid"
      end)
    end
  end

  describe "update" do
    alias Sanbase.Project

    test "reader webhook with exception", context do
      Utils
      |> Sanbase.Mock.prepare_mock(:clone_repo, fn _, _ ->
        raise("Some exception")
      end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert %{"error" => error} =
                 context.conn
                 |> post("/projects_data_reader_webhook/#{context.secret}", %{
                   "branch" => "some_branch",
                   "changed_files" => "projects/santiment/data.json"
                 })
                 |> json_response(400)

        assert error =~ "Some exception"
      end)
    end

    test "reader webhook with match error", context do
      Utils
      |> Sanbase.Mock.prepare_mock(:clone_repo, fn _, _ ->
        {:error, "Some unexpected error"}
      end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert %{"error" => error} =
                 context.conn
                 |> post("/projects_data_reader_webhook/#{context.secret}", %{
                   "branch" => "some_branch",
                   "changed_files" => "projects/santiment/data.json"
                 })
                 |> json_response(400)

        assert error =~ "Some unexpected error"
      end)
    end

    test "reader webhook", context do
      # Empty project. The factory adds some default values
      {:ok, _} =
        %Project{}
        |> Project.changeset(%{ticker: "SAN", name: "Santiment", slug: "santiment"})
        |> Sanbase.Repo.insert()

      Utils
      |> Sanbase.Mock.prepare_mock(:clone_repo, fn _, _ ->
        clone_repo_mock(context.path, Path.join(__DIR__, "data_correct.json"))
      end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        context.conn
        |> post("/projects_data_reader_webhook/#{context.secret}", %{
          "changed_files" => "projects/santiment/data.json"
        })
        |> json_response(200)
      end)

      project =
        Project.by_slug("santiment", preload: [:github_organizations, :contract_addresses])

      assert project.twitter_link == "https://twitter.com/santimentfeed"
      assert project.discord_link == "https://discord.com/santiment"
      assert project.github_organizations |> hd() |> Map.get(:organization) == "santiment"

      assert project.contract_addresses |> hd() |> Map.get(:address) ==
               "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"

      assert project.contract_addresses |> hd() |> Map.get(:decimals) == 18
    end

    test "reader webhook - update existing contract", context do
      # Empty project. The factory adds some default values
      {:ok, project} =
        %Project{}
        |> Project.changeset(%{ticker: "SAN", name: "Santiment", slug: "santiment"})
        |> Sanbase.Repo.insert()

      Project.ContractAddress.add_contract(project, %{
        address: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"
      })

      Utils
      |> Sanbase.Mock.prepare_mock(:clone_repo, fn _, _ ->
        clone_repo_mock(context.path, Path.join(__DIR__, "data_correct.json"))
      end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        context.conn
        |> post("/projects_data_reader_webhook/#{context.secret}", %{
          "changed_files" => "projects/santiment/data.json"
        })
        |> json_response(200)
      end)

      project = Project.by_slug("santiment", preload: [:contract_addresses])

      assert project.contract_addresses |> hd() |> Map.get(:address) ==
               "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"

      assert project.contract_addresses |> hd() |> Map.get(:decimals) == 18
    end
  end

  defp clone_repo_mock(destination, source_file) do
    path = Path.join([destination, "projects", "santiment"])
    File.mkdir_p!(path)
    File.cp!(source_file, Path.join([path, "data.json"]))

    repo = %Sanbase.RepoReader.Repository{path: destination}
    {:ok, repo}
  end
end
