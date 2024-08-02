defmodule Sanbase.Billing.Plan.CustomPlan.Restrictions do
  use Ecto.Schema

  import Ecto.Changeset

  embedded_schema do
    field(:restricted_access_as_plan, :string)

    field(:api_call_limits, :map)
    field(:historical_data_in_days, :integer)
    field(:realtime_data_cut_off_in_days, :integer)

    field(:metric_access, :map)
    field(:query_access, :map)
    field(:signal_access, :map)
  end

  @fields [
    :restricted_access_as_plan,
    :historical_data_in_days,
    :realtime_data_cut_off_in_days,
    :api_call_limits,
    :metric_access,
    :query_access,
    :signal_access
  ]

  @required_fields @fields -- [:historical_data_in_days, :realtime_data_cut_off_in_days]

  def changeset(%__MODULE__{} = plan, attrs) do
    plan
    |> cast(attrs, @fields)
    |> validate_required(@required_fields)
    |> validate_change(:api_call_limits, &validate_api_calls/2)
    |> validate_change(:metric_access, &validate_access_map/2)
    |> validate_change(:query_access, &validate_access_map/2)
    |> validate_change(:signal_access, &validate_access_map/2)
  end

  def create(args) do
    %__MODULE__{}
    |> changeset(args)
    |> Sanbase.Repo.insert()
  end

  def by_name(name) when is_binary(name) do
    case Sanbase.Repo.get_by(__MODULE__, name: name) do
      nil -> {:error, "Custom plan #{name} does not exist"}
      %__MODULE__{} = plan -> {:ok, plan}
    end
  end

  # Gets the number of API calls per month, hour and minute
  # Checks that month is bigger than hour, which is bigger
  # than minute, which is bigger than 0
  defguardp is_valid_limits_order(month, hour, minute)
            when month > hour and hour > minute and minute > 0

  defp validate_api_calls(:api_call_limits, %{} = api_calls) do
    case api_calls do
      %{"has_limits" => false} ->
        []

      %{"minute" => minute, "hour" => hour, "month" => month}
      when is_integer(minute) and is_integer(hour) and is_integer(month) and
             is_valid_limits_order(month, hour, minute) ->
        []

      _ ->
        [api_call_limits: "The api_call_limits map is not valid"]
    end
  end

  defp validate_access_map(field_name, %{} = access_map) do
    with true <- valid_accessible(access_map),
         true <- valid_not_accessible(access_map),
         true <- valid_not_accessible_patterns(access_map) do
      []
    else
      _ ->
        [{field_name, "The #{field_name} map is not valid"}]
    end
  end

  defp valid_accessible(%{"accessible" => "all"}), do: true
  defp valid_accessible(%{"accessible" => list}), do: Enum.all?(list, &is_binary/1)
  defp valid_not_accessible(%{"not_accessible" => "all"}), do: true
  defp valid_not_accessible(%{"not_accessible" => list}), do: Enum.all?(list, &is_binary/1)

  defp valid_not_accessible_patterns(%{"not_accessible_patterns" => list}),
    do: Enum.all?(list, &is_binary/1)
end
