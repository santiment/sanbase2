defmodule Sanbase.WatchlistFunction do
  use Vex.Struct

  defstruct name: "empty", args: []

  alias Sanbase.Model.Project

  @behaviour Ecto.Type
  def type, do: :map

  def evaluate(%__MODULE__{name: "market_segment", args: args}) do
    market_segment = Map.get(args, "market_segment") || Map.get(args, :market_segment)
    Project.List.by_market_segment(market_segment)
  end

  def evaluate(%__MODULE__{name: "top_erc20_projects", args: args}) do
    size = Map.get(args, "size") || Map.fetch!(args, :size)
    Project.List.erc20_projects_page(1, size)
  end

  def evaluate(%__MODULE__{name: "top_all_projects", args: args}) do
    size = Map.get(args, "size") || Map.fetch!(args, :size)
    Project.List.projects_page(1, size)
  end

  def evaluate(%__MODULE__{name: "min_volume", args: args}) do
    volume = Map.get(args, "min_volume") || Map.fetch!(args, :min_volume)
    Project.List.projects(volume)
  end

  def evaluate(%__MODULE__{name: "slugs", args: args}) do
    slugs = Map.get(args, "slugs") || Map.fetch!(args, :slugs)
    Project.List.by_slugs(slugs)
  end

  def evaluate(%__MODULE__{name: "empty"}), do: []

  def empty(), do: %__MODULE__{name: "empty", args: []}

  def cast(function) when is_binary(function) do
    parse(function)
  end

  def cast(%__MODULE__{} = function), do: {:ok, function}

  def cast(%{} = function) do
    atomized_fun =
      for {key, val} <- function, into: %{} do
        {String.to_existing_atom(key), val}
      end

    {:ok, struct!(__MODULE__, atomized_fun)}
  end

  def cast(_), do: :error

  def load(function) when is_map(function) do
    function =
      for {key, val} <- function do
        {String.to_existing_atom(key), val}
      end

    {:ok, struct!(__MODULE__, function)}
  end

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
