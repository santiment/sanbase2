defmodule Sanbase.RepoReader do
  @moduledoc ~s"""
  Provide validation and reading of a public repository holding projects data.

  The module provides 2 functions - validate_changes/2 and update_projects/1
  that clone the repository, read and parse the files and then do the correct
  action.
  """

  alias Sanbase.Model.Project
  alias __MODULE__.{Repository, Validator}

  import __MODULE__.Utils,
    only: [clone_repo: 1, clone_repo: 2, read_files: 2, files_to_directories: 1]

  require Logger

  @repository "projects_data"
  @repository_url "https://github.com/santiment/#{@repository}.git"

  @doc ~s"""
  Validate the changes in a PR opened in #{@repository_url}

  To make sure that the PRs do not introduce any errors, wrong types
  or values, execute validate them by using jsonschema and custom
  validations
  """
  @spec validate_changes(String.t(), list(String.t())) :: :ok | {:error, String.t()}
  def validate_changes(branch, changed_files_list) do
    path = Temp.mkdir!(@repository)

    changed_directories = files_to_directories(changed_files_list)

    result = do_validate_changes(path, branch, changed_directories)

    File.rm_rf!(path)

    case result do
      {:ok, _} -> :ok
      error -> error
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

    changed_directories = files_to_directories(changed_files_list)

    result = do_update_projects(path, changed_directories)

    File.rm_rf!(path)

    case result do
      {:ok, _} -> :ok
      error -> error
    end
  end

  # Private functions

  defp do_update_projects(path, changed_directories) do
    with {:ok, %Repository{} = repo} <- clone_repo(path),
         {:ok, projects_map} = read_files(repo, directories_to_read: changed_directories) do
      slugs = Map.keys(projects_map)
      projects = Sanbase.Model.Project.List.by_slugs(slugs)

      update_projects_data(projects, projects_map)
    end
  end

  defp do_validate_changes(path, branch, changed_directories) do
    with {:ok, %Repository{} = repo} <- clone_repo(path, branch: branch),
         {:ok, projects_map} = read_files(repo, directories_to_read: changed_directories),
         :ok <- Validator.validate(projects_map) do
      :ok
    end
  end

  defp update_projects_data(projects, projects_map) do
    Enum.reduce_while(projects, :ok, fn project, _acc ->
      data = Map.get(projects_map, project.slug)

      with :ok <- update_social_data(project, data),
           :ok <- update_development_data(project, data) do
        {:cont, :ok}
      else
        {:error, _} = error_tuple -> {:halt, error_tuple}
      end
    end)
  end

  defp update_social_data(project, data) do
    social = data["social"]

    result =
      Project.changeset(
        project,
        %{
          twitter_link: social["twitter"],
          discord_link: social["discord"],
          slack_link: social["slack"],
          facebook_link: social["facebook"],
          btt_link: social["bitcointalk"],
          reddit_link: social["reddit"],
          blog_link: social["blog"]
        }
      )
      |> Sanbase.Repo.update()

    case result do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp update_development_data(project, data) do
    organizations = data["development"]["github_organizations"] || []
    existing_organizations = Enum.map(project.github_organizations, & &1.organization)

    (organizations -- existing_organizations)
    |> Enum.reduce_while(:ok, fn org, _acc ->
      case Project.GithubOrganization.add_github_organization(project, org) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = error_tuple -> {:halt, error_tuple}
      end
    end)
  end
end
