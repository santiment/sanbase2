defmodule Sanbase.Metric.Registry.Validation do
  import Ecto.Changeset

  def validate_min_interval(:min_interval, min_interval) do
    if Sanbase.DateTimeUtils.valid_compound_duration?(min_interval) do
      if Sanbase.DateTimeUtils.str_to_days(min_interval) > 30 do
        [
          min_interval:
            "The provided min_interval #{min_interval} is too big - more than 30 days."
        ]
      else
        []
      end
    else
      [
        min_interval:
          "The provided min_interval #{min_interval} is not a valid duration - a number followed by one of: s (second), m (minute), h (hour) or d (day)"
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
        validate_parameters_match_captures(changeset)

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
end
