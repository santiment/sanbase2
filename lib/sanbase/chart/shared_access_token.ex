defmodule Sanbase.Chart.Configuration.SharedAccessToken do
  @moduledoc ~s"""
  Shared access token represents an access to the metrics and queries in
  a chart layout.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Chart.Configuration

  schema "shared_access_tokens" do
    field(:from, :utc_datetime)
    field(:to, :utc_datetime)
    field(:uuid, :string)

    belongs_to(:user, Sanbase.Accounts.User)
    belongs_to(:chart_configuration, Configuration)

    timestamps()
  end

  @fields [:uuid, :user_id, :chart_configuration_id, :from, :to]
  def changeset(%__MODULE__{} = sat, args) do
    sat
    |> cast(args, @fields)
    |> validate_required(@fields)
    |> foreign_key_constraint(
      :chart_configuration_id,
      name: :shared_access_tokens_chart_configuration_id_fkey
    )
  end

  @doc ~s"""
  Return the Shared Access Token associated with the given UUID.
  """
  @spec by_uuid(String.t()) :: {:ok, %__MODULE__{}} | {:error, String.t()}
  def by_uuid(uuid) do
    case Sanbase.Repo.get_by(__MODULE__, uuid: uuid) do
      %__MODULE__{} = token -> {:ok, token}
      nil -> {:error, "Shared Token with the given uuid does not exist"}
    end
  end

  @doc ~s"""
  Generate a Shared Access Token linked to a chart configuration
  """
  @spec generate(%Configuration{}, map()) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def generate(%Configuration{} = config, %{from: _, to: _} = args) do
    with true <- valid_params?(args) do
      args = %{
        uuid: generate_uuid(),
        from: args.from,
        to: args.to,
        user_id: config.user_id,
        chart_configuration_id: config.id
      }

      changeset(%__MODULE__{}, args)
      |> Sanbase.Repo.insert()
    end
  end

  @doc ~s"""
  Given a shared access token, return a map that also contains the metrics and queries
  exposed by the referenced chart configuration. The result is cached for performance
  reasons. If the owner of the shared access token is longer a Sanbase Pro user,
  an error is returned.
  """
  @spec get_resolved_token(%__MODULE__{}) ::
          {:ok,
           %{
             shared_access_token: %__MODULE__{},
             metrics: list(),
             queries: list(),
             plan: atom(),
             product_id: integer(),
             product: String.t()
           }}
          | {:error, String.t()}
  def get_resolved_token(%__MODULE__{} = token) do
    cache_key = {__MODULE__, :get_resolved_token, token.uuid} |> Sanbase.Cache.hash()

    Sanbase.Cache.get_or_store(cache_key, fn ->
      case Sanbase.Billing.Subscription.user_has_sanbase_pro?(token.user_id) do
        true ->
          {:ok, config} = Configuration.by_id(token.chart_configuration_id, preload: [:project])
          metrics = extract_metrics(config)
          queries = extract_queries(config)

          result = %{
            shared_access_token: token,
            metrics: metrics,
            queries: queries,
            plan: :pro,
            product_id: Sanbase.Billing.Product.product_sanbase(),
            product: "SANBASE"
          }

          {:ok, result}

        false ->
          {:error, "The owner of the shared token no longer has a Sanbase Pro subscription"}
      end
    end)
  end

  @uuid_length 12
  defp generate_uuid() do
    :crypto.strong_rand_bytes(@uuid_length)
    |> Base.url_encode64(padding: false)
    |> binary_part(0, @uuid_length)
  end

  defp extract_metrics(%Configuration{} = config) do
    config.metrics
    |> list_to_individual_entries(config.project)
  end

  defp extract_queries(%Configuration{} = config) do
    config.queries
    |> list_to_individual_entries(config.project)
  end

  defp list_to_individual_entries(nil, _project), do: []

  defp list_to_individual_entries(list, %Sanbase.Model.Project{slug: project_slug}) do
    list
    |> Enum.flat_map(fn entry ->
      String.split(entry, "__MM__")
    end)
    |> Enum.map(fn entry ->
      case String.split(entry, ["-CC-", "_MC_"]) do
        [slug, _ticker, metric] -> %{metric: Inflex.underscore(metric), slug: slug}
        [metric] -> %{metric: Inflex.underscore(metric), slug: project_slug}
      end
    end)
    |> Enum.uniq()
  end

  defp valid_params?(%{from: from, to: to}) do
    valid_datetime?(from) and valid_datetime?(to) and valid_datetime_range?(from, to)
  end

  defp valid_datetime?(%DateTime{} = dt) do
    case Timex.between?(dt, ~U[2009-01-01T00:00:00Z], Timex.now()) do
      true ->
        true

      false ->
        {:error, "The from-to parameters must be in the range between 2009-01-01 and UTC now."}
    end
  end

  defp valid_datetime_range?(from, to) do
    case DateTime.compare(from, to) do
      :lt -> true
      _ -> {:error, "The `to` parameter must be a later date than `from`."}
    end
  end
end
