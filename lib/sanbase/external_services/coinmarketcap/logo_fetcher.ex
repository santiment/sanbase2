defmodule Sanbase.ExternalServices.Coinmarketcap.LogoFetcher do
  use Tesla

  require Logger

  import Sanbase.Utils.ErrorHandling, only: [changeset_errors_string: 1]
  alias Sanbase.Project
  alias Sanbase.Model.LatestCoinmarketcapData
  alias Sanbase.Repo
  alias Sanbase.ExternalServices.Coinmarketcap.CryptocurrencyInfo
  alias Sanbase.FileStore
  alias Sanbase.Utils.FileHash

  @log_tag "[CMC][LogoFetcher]"
  @size 64

  def run() do
    projects = Project.List.projects_with_source("coinmarketcap", include_hidden: true)

    Logger.info("#{@log_tag} Started fetching logos from coinmarketcap.")

    dir_path = Temp.mkdir!("logos")

    projects
    |> Enum.chunk_every(100)
    |> Enum.each(fn projects ->
      {:ok, remote_projects} = CryptocurrencyInfo.fetch_data(projects)
      logo_map = remote_projects |> Enum.into(%{}, fn ci -> {ci.slug, ci.logo} end)

      Enum.each(projects, fn project ->
        update_project_logos(project, logo_map, dir_path)
      end)
    end)

    File.rm_rf!(dir_path)

    Logger.info("#{@log_tag} Finished fetching logos from coinmarketcap.")
  end

  # run for single project
  def run(slug) do
    project = Project.by_slug(slug)

    Logger.info("#{@log_tag} Started fetching logos from coinmarketcap.")
    dir_path = Temp.mkdir!("logotemp")

    {:ok, remote_projects} = CryptocurrencyInfo.fetch_data([project])
    logo_map = remote_projects |> Enum.into(%{}, fn ci -> {ci.slug, ci.logo} end)
    update_project_logos(project, logo_map, dir_path)

    File.rm_rf!(dir_path)
  end

  defp update_project_logos(project, logo_map, dir_path) do
    with coinmarketcap_id when not is_nil(coinmarketcap_id) <- Project.coinmarketcap_id(project),
         url when not is_nil(url) <- Map.get(logo_map, coinmarketcap_id),
         file_extension <- Path.extname(url |> String.downcase()),
         filename <- coinmarketcap_id <> file_extension,
         {:ok, local_filepath} <- download(url, dir_path, filename),
         true <- logo_changed?(project, local_filepath),
         {:ok, local_filepath} <- resize_image(local_filepath, dir_path, filename),
         {:ok, uploaded_filepath} <- upload(local_filepath),
         {:ok, _} <-
           update_local_project(project, %{
             logo_url: uploaded_filepath
           }) do
      Logger.info("#{@log_tag} Successfully updated logos for project: #{project.slug}")
    end
  end

  defp logo_changed?(project, filepath) do
    coinmarketcap_id = Project.coinmarketcap_id(project)

    case coinmarketcap_id && LatestCoinmarketcapData.get_or_build(coinmarketcap_id) do
      nil ->
        false

      latest_cmc_data ->
        {:ok, file_hash} = FileHash.calculate(filepath)

        case {latest_cmc_data.logo_hash, project.logo_url} do
          {^file_hash, nil} ->
            Logger.info("#{@log_tag} Logo for project: #{project.slug} has changed.")
            true

          {^file_hash, _} ->
            Logger.info("#{@log_tag} Logo for project: #{project.slug} has not changed.")
            false

          {_, _} ->
            latest_cmc_data
            |> LatestCoinmarketcapData.changeset(%{
              logo_hash: file_hash,
              logo_updated_at: Timex.now()
            })
            |> Repo.insert_or_update!()

            Logger.info("#{@log_tag} Logo for project: #{project.slug} has changed.")

            true
        end
    end
  end

  defp resize_image(source_path, dest_path, filename) do
    dest_filepath = dest_path <> "/" <> filename

    try do
      Mogrify.open(source_path)
      |> Mogrify.resize("#{@size}x#{@size}")
      |> Mogrify.custom("type", "PaletteAlpha")
      |> Mogrify.save(path: dest_filepath)
    rescue
      e ->
        Logger.info("#{@log_tag} exception: #{inspect(e)}")
        {:error, inspect(e)}
    end

    {:ok, dest_filepath}
  end

  defp download(url, dir_path, filename) do
    filepath = Path.join(dir_path, filename)

    case get(url) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Logger.info("#{@log_tag} Successfully downloaded logo: #{url}")
        File.write!(filepath, body)
        {:ok, filepath}

      {:ok, %Tesla.Env{status: status}} ->
        error_msg = "#{@log_tag} Failed downloading logo: #{url}. Status: #{status}"
        Logger.error(error_msg)
        {:error, error_msg}

      {:error, error} ->
        error_msg = inspect(error)
        Logger.error("#{@log_tag} Error downloading logo: #{url}. Error message: #{error_msg}")
        {:error, error_msg}
    end
  end

  defp upload(filepath) do
    case FileStore.store({filepath, "logo#{@size}"}) do
      {:ok, filename} ->
        Logger.info("#{@log_tag} Successfully uploaded logo from #{filepath} to: #{filename}")
        {:ok, FileStore.url({filename, "logo#{@size}"})}

      {:error, error} ->
        error_msg = inspect(error)

        Logger.error(
          "#{@log_tag} Failed uploading logo: #{filepath}. Error message: #{error_msg}"
        )

        {:error, error_msg}
    end
  end

  defp update_local_project(%Project{} = project, %{} = fields) do
    case Project.changeset(project, fields) |> Repo.update() do
      {:ok, schema} ->
        {:ok, schema}

      {:error, error} ->
        error_msg = changeset_errors_string(error)

        Logger.error(
          "#{@log_tag} Error updating project locally: #{project.slug}. Error message: #{error_msg}"
        )

        {:error, error_msg}
    end
  end
end
