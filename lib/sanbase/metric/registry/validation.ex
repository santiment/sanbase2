defmodule Sanbase.Metric.Registry.Validation do
  import Ecto.Changeset

  def validate_interval(column, value) when column in [:min_interval, :stabilization_period] do
    if Sanbase.DateTimeUtils.valid_compound_duration?(value) do
      if Sanbase.DateTimeUtils.str_to_days(value) > 30 do
        [
          {column, "The provided #{column} value #{value} is too big - more than 30 days."}
        ]
      else
        []
      end
    else
      [
        {column, "The provided #{column} value #{value} is not a valid duration - \
        a number followed by one of: s (second), m (minute), h (hour) or d (day)"}
      ]
    end
  end

  def validate_template_fields(%Ecto.Changeset{} = changeset) do
    is_template = get_field(changeset, :is_template)
    parameters = get_field(changeset, :parameters)

    cond do
      is_template and parameters == [] ->
        add_error(
          changeset,
          :parameters,
          "When the metric is labeled as template metric, parameters cannot be empty"
        )

      not is_template and parameters != [] ->
        add_error(
          changeset,
          :parameters,
          "When the metric is not labeled as template metric, the parameters must be empty"
        )

      is_template and parameters != [] ->
        changeset
        |> validate_parameters_match_captures()
        |> validate_parameter_values()

      true ->
        changeset
    end
  end

  def validate_parameters_match_captures(changeset) do
    parameters = get_field(changeset, :parameters)
    metric = get_field(changeset, :metric)
    internal_metric = get_field(changeset, :internal_metric)
    {:ok, captures1} = Sanbase.TemplateEngine.Captures.extract_captures(metric)
    {:ok, captures2} = Sanbase.TemplateEngine.Captures.extract_captures(internal_metric)
    captures = Enum.map(captures1 ++ captures2, & &1.inner_content) |> Enum.uniq() |> Enum.sort()
    parameter_keys = Enum.flat_map(parameters, &Map.keys/1) |> Enum.uniq() |> Enum.sort()

    if captures == parameter_keys do
      changeset
    else
      add_error(
        changeset,
        :parameters,
        """
        The provided parameters do not match the captures in the metric #{metric}.
        Captures: #{Enum.join(captures, ", ")},
        Parameters: #{Enum.join(parameter_keys, ", ")}
        """
      )
    end
  end

  @interval_parameters ["timebound", "sliding_window", "interval"]
  @number_parameters ["value", "period"]
  @suffixed_number_parameters ["threshold", "low", "high"]
  def validate_parameter_values(changeset) do
    parameters = get_field(changeset, :parameters)
    metric = get_field(changeset, :metric)

    invalid_parameters =
      parameters
      |> Enum.filter(fn map ->
        Enum.any?(map, fn
          # The interval-valued parameters must be something like "1d", "30d", "2y"
          {key, value} when key in ["low", "high"] ->
            not (suffixed_string_number?(value) or interval?(value) or value == "inf")

          {key, value} when key in @interval_parameters ->
            not interval?(value)

          {key, value} when key in @number_parameters ->
            # The number-valued parameters ust be a binary representing a number (integer or float)
            not is_binary(value) or not match?({_, ""}, Float.parse(value))

          {key, value} when key in @suffixed_number_parameters ->
            # The allowed values are numbers or numbers with suffix like k and M: 5, 1k, 10M
            not suffixed_string_number?(value) and not interval?(value)

          _ ->
            false
        end)
      end)

    if invalid_parameters == [] do
      changeset
    else
      add_error(
        changeset,
        :parameters,
        """
        There provided parameters have invalid values in the metric #{metric}. Different parameters have different constaints (interval, number, etc.)
        Invalid parameters: #{Enum.join(invalid_parameters, ", ")}
        """
      )
    end
  end

  defp interval?(value) do
    is_binary(value) and Sanbase.DateTimeUtils.valid_compound_duration?(value)
  end

  defp suffixed_string_number?(num) when is_binary(num) do
    case Float.parse(num) do
      {_value, ""} -> true
      {_value, suffix} when suffix in ["k", "M"] -> true
      _ -> false
    end
  end

  defp suffixed_string_number?(_), do: false
end
