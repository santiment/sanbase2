defmodule Sanbase.WatchlistFunction do
  use Ecto.Type
  @derive Jason.Encoder
  defstruct name: "empty", args: []

  @type result :: %{
          optional(:projects) => list(),
          optional(:blockchain_addresses) => list(),
          optional(:total_projects_count) => non_neg_integer(),
          optional(:total_blockchain_addresses_count) => non_neg_integer(),
          optional(:has_pagination?) => boolean(),
          optional(:all_included_slugs) => list(String.t()),
          optional(:all_included_blockchain_addresses) => list(String.t())
        }

  alias Sanbase.Model.Project
  alias Sanbase.BlockchainAddress

  @impl Ecto.Type
  def type, do: :map

  @doc ~s"""
  Get a function defined as a map (either with atom or string keys) and returns
  the WatchlistFunction struct. The validation can be done either by trying to
  evaluate the function or not. In order to not evaluate the
  `check_function_evaluates: false` option must be provided in opts. This is
  only desirable if we are not storing the watchlist
  """
  def new(%{} = function, opts \\ []) do
    with {:ok, %__MODULE__{} = fun} <- cast(function),
         true <- valid_function?(fun, opts) do
      fun
    end
  end

  @address_selector_fields ["filters", "filters_combinator"]
  def valid_function?(fun, opts \\ [])

  def valid_function?(%__MODULE__{name: "address_selector", args: args} = fun, opts) do
    args = Enum.into(args, %{}, fn {k, v} -> {Inflex.underscore(k), v} end)

    with {selector, empty_map} when map_size(empty_map) == 0 <-
           Map.split(args, @address_selector_fields),
         true <- BlockchainAddress.ListSelector.valid_selector?(%{selector: selector}) do
      maybe_check_evaluates(fun, opts)
    else
      {%{}, %{} = unsupported_keys_map} when map_size(unsupported_keys_map) > 0 ->
        {:error,
         "Dynamic watchlist 'address_selector' has unsupported fields: #{inspect(Map.keys(unsupported_keys_map))}"}

      {:error, error} ->
        {:error, error}
    end
  end

  @project_selector_fields [
    "filters",
    "order_by",
    "pagination",
    "filters_combinator",
    "base_projects"
  ]
  def valid_function?(%__MODULE__{name: "selector", args: args} = fun, opts) do
    args = Enum.into(args, %{}, fn {k, v} -> {Inflex.underscore(k), v} end)

    with {selector, empty_map} when map_size(empty_map) == 0 <-
           Map.split(args, @project_selector_fields),
         true <- Project.ListSelector.valid_selector?(%{selector: selector}) do
      # returns `true` or `false` whether the function can be evaluated. This catches all
      # errors that can lead to the function being invalid.
      maybe_check_evaluates(fun, opts)
    else
      {%{}, %{} = unsupported_keys_map} when map_size(unsupported_keys_map) > 0 ->
        {:error,
         "Dynamic watchlist 'selector' has unsupported fields: #{inspect(Map.keys(unsupported_keys_map))}"}

      {:error, error} ->
        {:error, error}
    end
  end

  def valid_function?(%__MODULE__{name: "market_segment", args: args} = fun, opts) do
    market_segment = Map.get(args, "market_segment") || Map.fetch!(args, :market_segment)

    case is_binary(market_segment) do
      true -> maybe_check_evaluates(fun, opts)
      false -> {:error, "The market_segment argument must be a string."}
    end
  end

  def valid_function?(%__MODULE__{name: "market_segments", args: args} = fun, opts) do
    market_segment = Map.get(args, "market_segments") || Map.fetch!(args, :market_segments)

    case is_list(market_segment) and market_segment != [] do
      true -> maybe_check_evaluates(fun, opts)
      false -> {:error, "The market_segments argument must be a non-empty list."}
    end
  end

  def valid_function?(%__MODULE__{name: "top_erc20_projects", args: args} = fun, opts) do
    size = Map.get(args, "size") || Map.fetch!(args, :size)
    ignored_projects = Map.get(args, "ignored_projects") || Map.get(args, :ignored_projects) || []

    case is_integer(size) and size > 0 do
      false ->
        {:error, "The size argument must be a positive integer."}

      true ->
        case is_list(ignored_projects) do
          true -> maybe_check_evaluates(fun, opts)
          false -> {:error, "The ignored projects argument must be a list."}
        end
    end
  end

  def valid_function?(%__MODULE__{name: "top_all_projects", args: args} = fun, opts) do
    size = Map.get(args, "size") || Map.fetch!(args, :size)
    ignored_projects = Map.get(args, "ignored_projects") || Map.get(args, :ignored_projects) || []

    case is_integer(size) and size > 0 do
      false ->
        {:error, "The size argument must be a positive integer."}

      true ->
        case is_list(ignored_projects) do
          true -> maybe_check_evaluates(fun, opts)
          false -> {:error, "The ignored projects argument must be a list."}
        end
    end
  end

  def valid_function?(%__MODULE__{name: "min_volume", args: args} = fun, opts) do
    min_volume = Map.get(args, "min_volume") || Map.fetch!(args, :min_volume)

    case is_number(min_volume) and min_volume >= 0 do
      true -> maybe_check_evaluates(fun, opts)
      false -> {:error, "The min volume argument must be a non-negative number."}
    end
  end

  def valid_function?(%__MODULE__{name: "slugs", args: args} = fun, opts) do
    slugs = Map.get(args, "slugs") || Map.fetch!(args, :slugs)

    case is_list(slugs) and slugs != [] do
      true -> maybe_check_evaluates(fun, opts)
      false -> {:error, "The slugs argument must be a non-empty list."}
    end
  end

  def valid_function?(%__MODULE__{name: "trending_projects"}, _opts), do: true

  def valid_function?(%__MODULE__{name: "empty"}, _opts), do: true

  @doc ~s"""
  Checks if function evaluates. This is used as a last resort to checking if a
  function is valid as some edge cases can be missed. Creating a watchlist
  with a function that cannot be evaluated will cause constant errors on runtime.
  """
  @spec evaluates?(%__MODULE__{}) :: boolean()
  def evaluates?(%__MODULE__{} = fun) do
    try do
      case evaluate(fun) do
        {:ok, _} ->
          true

        {:error, error} ->
          {:error,
           "Watchlist function is not valid because it returns error when evaluating. Reason: #{inspect(error)}"}
      end
    rescue
      e ->
        {:error,
         "Watchlist function is not valid because it raises when evaluating. Reason: #{Exception.message(e)}"}
    end
  end

  @spec evaluate(%__MODULE__{}) ::
          {:ok, result} | {:error, String.t()}
  def evaluate(watchlist_function)

  def evaluate(%__MODULE__{name: "address_selector", args: args}) do
    args = Enum.into(args, %{}, fn {k, v} -> {Inflex.underscore(k), v} end)

    case Map.split(args, @address_selector_fields) do
      {selector, empty_map} when map_size(empty_map) == 0 ->
        BlockchainAddress.ListSelector.addresses(%{selector: selector})

      {_selector, unsupported_keys_map} ->
        {:error,
         "Dynamic watchlist 'address_selector' has unsupported fields: #{inspect(Map.keys(unsupported_keys_map))}"}
    end
  end

  def evaluate(%__MODULE__{name: "selector", args: args}) do
    args = Enum.into(args, %{}, fn {k, v} -> {Inflex.underscore(k), v} end)

    case Map.split(args, @project_selector_fields) do
      {selector, empty_map} when map_size(empty_map) == 0 ->
        Project.ListSelector.projects(%{selector: selector})

      {_selector, unsupported_keys_map} ->
        {:error,
         "Dynamic watchlist 'selector' has unsupported fields: #{inspect(Map.keys(unsupported_keys_map))}"}
    end
  end

  def evaluate(%__MODULE__{name: "market_segment", args: args}) do
    market_segment = Map.get(args, "market_segment") || Map.fetch!(args, :market_segment)
    projects = Project.List.by_market_segment_any_of(market_segment)

    {:ok,
     %{
       projects: projects,
       total_projects_count: length(projects)
     }}
  end

  def evaluate(%__MODULE__{name: "market_segments", args: args}) do
    market_segments = Map.get(args, "market_segments") || Map.fetch!(args, :market_segments)
    projects = Project.List.by_market_segment_all_of(market_segments)

    {:ok,
     %{
       projects: projects,
       total_projects_count: length(projects)
     }}
  end

  def evaluate(%__MODULE__{name: "top_erc20_projects", args: args}) do
    size = Map.get(args, "size") || Map.fetch!(args, :size)
    ignored_projects = Map.get(args, "ignored_projects") || Map.get(args, :ignored_projects) || []
    ignored_projects_mapset = MapSet.new(ignored_projects)

    projects =
      Project.List.erc20_projects_page(1, size + length(ignored_projects))
      |> Enum.reject(fn %Project{slug: slug} -> slug in ignored_projects_mapset end)
      |> Enum.take(size)

    {:ok,
     %{
       projects: projects,
       total_projects_count: length(projects)
     }}
  end

  def evaluate(%__MODULE__{name: "top_all_projects", args: args}) do
    size = Map.get(args, "size") || Map.fetch!(args, :size)
    ignored_projects = Map.get(args, "ignored_projects") || Map.get(args, :ignored_projects) || []
    ignored_projects_mapset = MapSet.new(ignored_projects)

    projects =
      Project.List.projects_page(1, size + length(ignored_projects))
      |> Enum.reject(fn %Project{slug: slug} -> slug in ignored_projects_mapset end)
      |> Enum.take(size)

    {:ok,
     %{
       projects: projects,
       total_projects_count: length(projects)
     }}
  end

  def evaluate(%__MODULE__{name: "min_volume", args: args}) do
    min_volume = Map.get(args, "min_volume") || Map.fetch!(args, :min_volume)
    projects = Project.List.projects(min_volume: min_volume)

    {:ok,
     %{
       projects: projects,
       total_projects_count: length(projects)
     }}
  end

  def evaluate(%__MODULE__{name: "slugs", args: args}) do
    slugs = Map.get(args, "slugs") || Map.fetch!(args, :slugs)
    projects = Project.List.by_slugs(slugs)

    {:ok,
     %{
       projects: projects,
       total_projects_count: length(projects)
     }}
  end

  def evaluate(%__MODULE__{name: "trending_projects"}) do
    projects = Project.List.currently_trending_projects()

    {:ok,
     %{
       projects: projects,
       total_projects_count: length(projects)
     }}
  end

  def evaluate(%__MODULE__{name: "empty"}) do
    {:ok,
     %{
       blockchain_addresses: [],
       total_blockchain_addresses_count: 0,
       projects: [],
       total_projects_count: 0
     }}
  end

  def empty(), do: %__MODULE__{name: "empty", args: []}

  @impl Ecto.Type
  def cast(function) when is_binary(function), do: parse(function)

  @impl Ecto.Type
  def cast(%__MODULE__{} = function), do: {:ok, function}

  def cast(%{} = function) do
    atomized_fun =
      for {key, val} <- function, into: %{} do
        if is_binary(key) do
          {key |> Inflex.underscore() |> String.to_existing_atom(), val}
        else
          {key, val}
        end
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

  defp maybe_check_evaluates(fun, opts) do
    case Keyword.get(opts, :check_function_evaluates, true) do
      true -> evaluates?(fun)
      false -> true
    end
  end
end
