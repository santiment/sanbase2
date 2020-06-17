defmodule Sanbase.WatchlistFunction do
  use Ecto.Type

  defstruct name: "empty", args: []

  alias Sanbase.Model.Project

  @impl Ecto.Type
  def type, do: :map

  def evaluate(%__MODULE__{name: "selector", args: args}) do
    case Map.split(args, ["filters", "order", "pagination"]) do
      {selector, empty_map} when map_size(empty_map) == 0 ->
        {:ok, projects} = Project.ListSelector.projects(%{selector: selector})
        projects

      {_selector, unsupported_keys_map} ->
        {:error,
         "Dynamic watchlist 'selector' has unsupported fields: #{
           inspect(Map.keys(unsupported_keys_map))
         }"}
    end
  end

  def evaluate(%__MODULE__{name: "market_segment", args: args}) do
    market_segment = Map.get(args, "market_segment") || Map.fetch!(args, :market_segment)
    Project.List.by_market_segment_any_of(market_segment)
  end

  def evaluate(%__MODULE__{name: "market_segments", args: args}) do
    market_segments = Map.get(args, "market_segments") || Map.fetch!(args, :market_segments)
    Project.List.by_market_segment_all_of(market_segments)
  end

  def evaluate(%__MODULE__{name: "top_erc20_projects", args: args}) do
    size = Map.get(args, "size") || Map.fetch!(args, :size)
    ignored_projects = Map.get(args, "ignored_projects") || Map.get(args, :ignored_projects) || []

    Project.List.erc20_projects_page(1, size + length(ignored_projects))
    |> Enum.reject(fn %Project{slug: slug} -> Enum.member?(ignored_projects, slug) end)
    |> Enum.take(size)
  end

  def evaluate(%__MODULE__{name: "top_all_projects", args: args}) do
    size = Map.get(args, "size") || Map.fetch!(args, :size)
    Project.List.projects_page(1, size)
  end

  def evaluate(%__MODULE__{name: "min_volume", args: args}) do
    min_volume = Map.get(args, "min_volume") || Map.fetch!(args, :min_volume)
    Project.List.projects(min_volume: min_volume)
  end

  def evaluate(%__MODULE__{name: "slugs", args: args}) do
    slugs = Map.get(args, "slugs") || Map.fetch!(args, :slugs)
    Project.List.by_slugs(slugs)
  end

  def evaluate(%__MODULE__{name: "trending_projects"}) do
    Project.List.currently_trending_projects()
  end

  def evaluate(%__MODULE__{name: "empty"}), do: []

  def empty(), do: %__MODULE__{name: "empty", args: []}

  @impl Ecto.Type
  def cast(function) when is_binary(function) do
    parse(function)
  end

  @impl Ecto.Type
  def cast(%__MODULE__{} = function), do: {:ok, function}

  def cast(%{} = function) do
    atomized_fun =
      for {key, val} <- function, into: %{} do
        {String.to_existing_atom(key), val}
      end

    {:ok, struct!(__MODULE__, atomized_fun)}
  end

  def cast(_), do: :error

  @impl Ecto.Type
  def load(function) when is_map(function) do
    function =
      for {key, val} <- function do
        {String.to_existing_atom(key), val}
      end

    {:ok, struct!(__MODULE__, function)}
  end

  @impl Ecto.Type
  def dump(%__MODULE__{} = function), do: {:ok, Map.from_struct(function)}
  def dump(_), do: :error

  # Private functions

  defp parse(str) when is_binary(str) do
    with {:ok, function} <- Jason.decode(str) do
      atomized_fun =
        for {key, val} <- function, into: %{} do
          {String.to_existing_atom(key), val}
        end

      {:ok, atomized_fun}
    end
  end
end
