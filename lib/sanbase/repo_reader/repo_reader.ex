defmodule Sanbase.RepoReader do
  @moduledoc ~s"""
  Provide validation and reading of a public repository holding projects data.

  The module provides 2 functions - validate_changes/2 and update_projects/1
  that clone the repository, read and parse the files and then do the correct
  action.
  """

  import __MODULE__.Utils,
    only: [
      clone_repo: 2,
      read_files: 2,
      files_to_directories: 1,
      repository: 0,
      repository_url: 0
    ]

  alias __MODULE__.Repository
  alias __MODULE__.Validator
  alias Sanbase.Project

  require Logger

  @repository repository()
  @repository_url repository_url()

  @doc ~s"""
  Validate the changes in a PR opened in #{@repository_url}

  To make sure that the PRs do not introduce any errors, wrong types
  or values, execute validate them by using jsonschema and custom
  validations
  """
  @spec validate_changes(String.t(), String.t(), String.t()) :: :ok | {:error, String.t()}
  def validate_changes(fork_repo, branch, changed_files_list) do
    # Replace / with : so it is not interpreted as directories.
    # fork_repo is in the form organization/repository
    path = Temp.mkdir!(String.replace(fork_repo, "/", ":"))

    try do
      changed_directories = files_to_directories(changed_files_list)
      result = do_validate_changes(path, fork_repo, branch, changed_directories)

      File.rm_rf!(path)

      result
    rescue
      error ->
        File.rm_rf!(path)
        {:error, Exception.message(error)}
    end
  end

  @doc ~s"""
  Update the projects changed in a master branch merge in #{@repository_url}

  When new commits are pushed to the main branch of the repository, github
  sends a webhook event for it. This function clones the repo and uses the changed
  files to update the appropriate projects.
  """
  @spec update_projects(list(String.t())) :: :ok | {:error, String.t()}
  def update_projects(changed_files_list) do
    path = Temp.mkdir!(@repository)

    try do
      changed_directories = files_to_directories(changed_files_list)

      result = do_update_projects(path, changed_directories)

      File.rm_rf!(path)
      result
    rescue
      error ->
        File.rm_rf!(path)
        {:error, Exception.message(error)}
    end
  end

  # Private functions

  defp do_update_projects(path, changed_directories) do
    with {:ok, %Repository{} = repo} <- clone_repo(path, branch: "main"),
         {:ok, projects_map} <- read_files(repo, directories_to_read: changed_directories) do
      slugs = Map.keys(projects_map)

      projects = Project.List.by_slugs(slugs)

      update_projects_data(projects, projects_map)
    end
  end

  defp do_validate_changes(path, fork_repo, branch, changed_directories) do
    with {:ok, %Repository{} = repo} <- clone_repo(path, fork_repo: fork_repo, branch: branch),
         {:ok, projects_map} <- read_files(repo, directories_to_read: changed_directories) do
      Validator.validate(projects_map)
    end
  end

  defp update_projects_data(projects, projects_map) do
    Enum.reduce_while(projects, :ok, fn project, _acc ->
      data = Map.get(projects_map, project.slug)

      with :ok <- update_general_data(project, data),
           :ok <- update_social_data(project, data),
           :ok <- update_development_data(project, data),
           :ok <- update_contracts_data(project, data) do
        {:cont, :ok}
      else
        {:error, _} = error_tuple -> {:halt, error_tuple}
      end
    end)
  end

  defp update_general_data(project, data) do
    general = data["general"]

    result =
      project
      |> Project.changeset(%{
        name: general["name"],
        ticker: general["ticker"],
        description: general["description"],
        ecosystem: general["ecosystem"],
        website: general["website"]
      })
      |> Sanbase.Repo.update()

    case result do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp update_social_data(project, data) do
    social = data["social"]

    result =
      project
      |> Project.changeset(%{
        twitter_link: social["twitter"],
        discord_link: social["discord"],
        slack_link: social["slack"],
        facebook_link: social["facebook"],
        btt_link: social["bitcointalk"],
        reddit_link: social["reddit"],
        blog_link: social["blog"]
      })
      |> Sanbase.Repo.update()

    case result do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp update_development_data(project, data) do
    organizations = data["development"]["github_organizations"] || []
    existing_organizations = Enum.map(project.github_organizations, & &1.organization)

    Enum.reduce_while(organizations -- existing_organizations, :ok, fn org, _acc ->
      case Project.GithubOrganization.add_github_organization(project, org) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = error_tuple -> {:halt, error_tuple}
      end
    end)
  end

  defp update_contracts_data(project, data) do
    contracts = data["blockchain"]["contracts"] || []

    Enum.reduce_while(contracts, :ok, fn contract_map, _acc ->
      args = %{
        address: Sanbase.BlockchainAddress.to_internal_format(contract_map["address"]),
        decimals: contract_map["decimals"],
        label: contract_map["label"],
        description: contract_map["description"]
      }

      case Project.ContractAddress.add_contract(project, args) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = error_tuple -> {:halt, error_tuple}
      end
    end)
  end
end
