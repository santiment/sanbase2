defmodule SanbaseWeb.Graphql.Resolvers.MetricTransform do
  @transform_types [
    "none",
    "cumulative_sum",
    "z_score",
    "moving_average",
    "changes",
    "consecutive_differences",
    "percent_change",
    "cumulative_percent_change"
  ]

  def transform_types(), do: @transform_types

  def args_to_transform(args) do
    transform =
      args
      |> Map.get(:transform, %{type: "none"})
      |> Map.update!(:type, &Inflex.underscore/1)

    case transform.type in @transform_types do
      true ->
        {:ok, transform}

      false ->
        {:error, "Transform type '#{transform.type}' is not supported or is mistyped.\
        Supported types are: #{Enum.join(@transform_types, ", ")}"}
    end
  end

  def calibrate_transform_params(%{type: type}, from, _to, _interval)
      when type in ["none", "cumulative_sum", "z_score"] do
    {:ok, from}
  end

  def calibrate_transform_params(
        %{type: "moving_average", moving_average_base: base},
        from,
        _to,
        interval
      ) do
    shift_by_sec = base * Sanbase.DateTimeUtils.str_to_sec(interval)
    from = Timex.shift(from, seconds: -shift_by_sec)
    {:ok, from}
  end

  def calibrate_transform_params(%{type: type}, from, _to, interval)
      when type in [
             "changes",
             "consecutive_differences",
             "percent_change",
             "cumulative_percent_change"
           ] do
    shift_by_sec = Sanbase.DateTimeUtils.str_to_sec(interval)
    from = Timex.shift(from, seconds: -shift_by_sec)
    {:ok, from}
  end

  def calibrate_transform_params(%{type: type}, _from, _to, _interval) do
    {:error, "The transform type '#{type}' is not supported or is mistyped."}
  end

  def apply_transform(%{type: "none"}, data), do: {:ok, data}

  def apply_transform(
        %{type: "moving_average", moving_average_base: base},
        data
      ) do
    Sanbase.Math.simple_moving_average(data, base, value_key: :value)
  end

  def apply_transform(
        %{type: "z_score"},
        data
      ) do
    numbers_list = Enum.map(data, & &1.value)

    case Sanbase.Math.zscore(numbers_list) do
      {:error, error} ->
        {:error, error}

      z_score_series ->
        result =
          Enum.zip_with(data, z_score_series, fn point, z_score ->
            Map.put(point, :value, z_score)
          end)

        {:ok, result}
    end
  end

  def apply_transform(%{type: type}, data)
      when type in ["changes", "consecutive_differences"] do
    result =
      Stream.chunk_every(data, 2, 1, :discard)
      |> Enum.map(fn [%{value: previous}, %{value: current, datetime: datetime}] ->
        %{
          datetime: datetime,
          value: current - previous
        }
      end)

    {:ok, result}
  end

  def apply_transform(%{type: type}, data) when type in ["cumulative_sum"] do
    result =
      data
      |> Enum.scan(fn %{value: current} = elem, %{value: previous} ->
        %{elem | value: current + previous}
      end)

    {:ok, result}
  end

  def apply_transform(%{type: type}, data) when type in ["percent_change"] do
    result =
      Stream.chunk_every(data, 2, 1, :discard)
      |> Enum.map(fn [%{value: previous}, %{value: current, datetime: datetime}] ->
        %{
          datetime: datetime,
          value: Sanbase.Math.percent_change(previous, current)
        }
      end)

    {:ok, result}
  end

  def apply_transform(%{type: type}, data)
      when type in ["cumulative_percent_change"] do
    {:ok, cumsum} = apply_transform(%{type: "cumulative_sum"}, data)
    apply_transform(%{type: "percent_change"}, cumsum)
  end
end
