defmodule Sanbase.RepoReader.Utils do
  alias Sanbase.RepoReader.Repository

  require Logger

  @repository "projects_data"
  @repository_url "https://github.com/santiment/#{@repository}.git"

  def repository(), do: @repository
  def repository_url(), do: @repository_url

  @doc ~s"""
  Clone the repository as specified by the module attribute and store
  the files in the specified path
  """
  @spec clone_repo(String.t(), Keyword.t()) :: {:ok, Repository.t()} | {:error, String.t()}
  def clone_repo(path, opts) do
    Logger.info("Cloning reposistory #{@repository}...")

    fork_repo = Keyword.fetch!(opts, :fork_repo)
    branch = Keyword.fetch!(opts, :branch)

    case System.cmd(
           "git",
           ["clone", "--single-branch", "--branch", branch, repository_url(fork_repo), path],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        Logger.info("Cloned repository #{@repository}. Output: #{inspect(output)}")
        {:ok, %Repository{path: path}}

      {error, code} ->
        {:error,
         "Error code #{inspect(code)} cloning repository #{@repository_url}: #{inspect(error)}"}
    end
  end

  defp repository_url(fork_repo) do
    # People submit PRs from their own forks. In such case we should clone their repo,
    # not ours.
    "https://github.com/#{fork_repo}.git"
  end

  @doc ~s"""
  Read the files in the given repository and present them as
  a map where the key is the directory name and the value is the
  data.json file parsed into Elixir map.

  The options must contain the :directories_to_read key. It contains
  the list of directories that have files that have changed.
  """
  def read_files(%Repository{path: path}, opts) do
    projects_path = Path.join([path, "projects"])

    directories = get_directories(projects_path, opts)

    list = get_ok_error_file_data_tuples_list(projects_path, directories)
    # The list contains tuples {:ok, slug, data} and {:error, dir, error}.
    # Group by the first element and return error if there are any errors
    errors_and_oks = Enum.group_by(list, fn {res, _, _} -> res end, fn {_res, l, r} -> {l, r} end)

    case errors_and_oks do
      %{error: [_ | _] = errors} ->
        error_msg =
          Enum.map(errors, fn {dir, error} ->
            ["Found error in directory #{dir}: #{inspect(error)}"]
          end)
          |> Enum.join("\n")

        {:error, error_msg}

      %{ok: slug_data_pairs} ->
        # the value is the list of {slug, data} tuples
        {:ok, Map.new(slug_data_pairs)}
    end
  end

  @doc ~s"""

  Examples:
    iex> Sanbase.RepoReader.Utils.files_to_directories("projects/santiment/data.json,projects/santiment/logo.svg,projects/bitcoin/data.json")
    ["santiment", "bitcoin"]

    iex> Sanbase.RepoReader.Utils.files_to_directories("projects/santiment/data.json")
    ["santiment"]
  """
  def files_to_directories(changed_files_string) do
    changed_files_string
    |> String.split(",")
    |> Enum.filter(&String.starts_with?(&1, "projects/"))
    |> Enum.map(fn path ->
      [_projects, directory | _rest] = String.split(path, "/")
      directory
    end)
    |> Enum.uniq()
  end

  # Private functions

  defp get_directories(path, opts) do
    {:ok, directories} = File.ls(path)

    directories_to_read =
      Keyword.fetch!(opts, :directories_to_read)
      |> MapSet.new()

    directories
    |> Enum.reject(fn dir ->
      # Remove directories like .git. Read only the changed files
      String.starts_with?(dir, ".") or dir not in directories_to_read
    end)
  end

  defp get_slug(data) do
    case data do
      %{"general" => %{"slug" => slug}} when is_binary(slug) -> {:ok, slug}
      _ -> {:error, "No slug found or it is not a string"}
    end
  end

  defp get_ok_error_file_data_tuples_list(path, directories) do
    directories
    |> Enum.map(fn dir ->
      directory = Path.join([path, dir])
      data_file_path = Path.join([directory, "data.json"])

      with {:ok, file_content} <- File.read(data_file_path),
           {:ok, data} <- Jason.decode(file_content),
           {:ok, slug} when is_binary(slug) <- get_slug(data) do
        {:ok, slug, data}
      else
        {:error, error} ->
          Logger.warning("""
          Error reading/decoding a #{@repository} file in directory: #{dir}.
          Reason: #{inspect(error)}
          """)

          {:error, dir, error}
      end
    end)
  end
end
