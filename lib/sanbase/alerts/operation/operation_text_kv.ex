defmodule Sanbase.Alert.OperationText.KV do
  @moduledoc ~s"""
  A module providing a single function to_template_kv/3 which transforms an operation
  to human readable text that can be included in the alert's payload
  """

  def current_value(%{current: value, previous: previous}, opts) do
    special_symbol = Keyword.get(opts, :special_symbol, "")
    transform_fun = Keyword.get(opts, :value_transform, fn x -> x end)

    template =
      "Was: #{special_symbol}{{previous:human_readable}}\nNow: #{special_symbol}{{value:human_readable}}"

    kv = %{
      value: transform_fun.(value),
      previous: transform_fun.(previous)
    }

    {template, kv}
  end

  def current_value(%{current: value}, opts) do
    special_symbol = Keyword.get(opts, :special_symbol, "")
    transform_fun = Keyword.get(opts, :value_transform, fn x -> x end)

    template = "Now: #{special_symbol}{{value:human_readable}}"
    kv = %{value: transform_fun.(value)}
    {template, kv}
  end

  defguard is_absolute_value_operation(map)
           when (map_size(map) == 1 and
                   is_map_key(map, :above)) or is_map_key(map, :above_or_equal) or
                  is_map_key(map, :below) or is_map_key(map, :below_or_equal)

  def to_template_kv(value, operation, opts \\ [])

  # Absolute value operations (below, below_or_equal, above, above_or_equal)
  def to_template_kv(%{current: value}, %{} = op, opts) when is_absolute_value_operation(op),
    do: to_template_kv(value, op, opts)

  def to_template_kv(value, op, opts) when is_absolute_value_operation(op) do
    [op_key | _] = Map.keys(op)
    op_value = op[op_key]

    form = opts |> Keyword.get(:form, :singular) |> form_to_text()
    special_symbol = Keyword.get(opts, :special_symbol, "")
    transform_fun = Keyword.get(opts, :value_transform, fn x -> x end)

    op_to_text = fn op ->
      op
      |> Atom.to_string()
      |> String.replace("_", " ")
    end

    template =
      if Keyword.get(opts, :negative, false) do
        "#{form} not #{op_to_text.(op_key)} #{special_symbol}{{#{op_key}:human_readable}}"
      else
        "#{form} #{op_to_text.(op_key)} #{special_symbol}{{#{op_key}:human_readable}}"
      end

    kv = %{
      op_key => transform_fun.(op_value),
      value: transform_fun.(value)
    }

    {template, kv}
  end

  # Inside channel
  def to_template_kv(%{current: value}, %{inside_channel: _} = op, opts), do: to_template_kv(value, op, opts)

  def to_template_kv(value, %{inside_channel: [lower, upper]}, opts) do
    form = opts |> Keyword.get(:form, :singular) |> form_to_text()
    special_symbol = Keyword.get(opts, :special_symbol, "")
    transform_fun = Keyword.get(opts, :value_transform, fn x -> x end)

    template =
      if Keyword.get(opts, :negative, false) do
        "#{form} not inside the [#{special_symbol}{{lower:human_readable}}, #{special_symbol}{{upper:human_readable}}] interval"
      else
        "#{form} inside the [#{special_symbol}{{lower:human_readable}}, #{special_symbol}{{upper:human_readable}}] interval"
      end

    kv = %{
      lower: transform_fun.(lower),
      upper: transform_fun.(upper),
      value: transform_fun.(value)
    }

    {template, kv}
  end

  # Outside channel
  def to_template_kv(%{current: value}, %{outside_channel: _} = op, opts), do: to_template_kv(value, op, opts)

  def to_template_kv(value, %{outside_channel: [lower, upper]}, opts) do
    form = opts |> Keyword.get(:form, :singular) |> form_to_text()
    special_symbol = Keyword.get(opts, :special_symbol, "")
    transform_fun = Keyword.get(opts, :value_transform, fn x -> x end)

    template =
      if Keyword.get(opts, :negative, false) do
        "#{form} not outside the [#{special_symbol}{{lower:human_readable}}, #{special_symbol}{{upper:human_readable}}] interval"
      else
        "#{form} outside the [#{special_symbol}{{lower:human_readable}}, #{special_symbol}{{upper:human_readable}}] interval"
      end

    kv = %{
      lower: transform_fun.(lower),
      upper: transform_fun.(upper),
      value: transform_fun.(value)
    }

    {template, kv}
  end

  # Percent up
  def to_template_kv(%{percent_change: value}, %{percent_up: _} = op, opts), do: to_template_kv(value, op, opts)

  def to_template_kv(percent_change, %{percent_up: percent_up}, opts) do
    transform_fun = Keyword.get(opts, :value_transform, fn x -> x end)

    template =
      if Keyword.get(opts, :negative, false) do
        "did not increase by {{percent_up_required}}%"
      else
        "increased by {{percent_up}}%"
      end

    kv = %{
      percent_up: transform_fun.(percent_change),
      percent_up_required: transform_fun.(percent_up)
    }

    {template, kv}
  end

  # Percent down
  def to_template_kv(%{percent_change: value}, %{percent_down: _} = op, opts), do: to_template_kv(value, op, opts)

  def to_template_kv(percent_change, %{percent_down: percent_down}, opts) do
    transform_fun = Keyword.get(opts, :value_transform, fn x -> x end)

    template =
      if Keyword.get(opts, :negative, false) do
        "did not decrease by {{percent_down_required}}%"
      else
        "decreased by {{percent_down}}%"
      end

    kv = %{
      percent_down: percent_change |> transform_fun.() |> abs(),
      percent_down_required: transform_fun.(percent_down)
    }

    {template, kv}
  end

  # Amount up
  def to_template_kv(%{absolute_change: value}, %{amount_up: _} = op, opts), do: to_template_kv(value, op, opts)

  def to_template_kv(amount_change, %{amount_up: amount_up}, opts) do
    special_symbol = Keyword.get(opts, :special_symbol, "")
    transform_fun = Keyword.get(opts, :value_transform, fn x -> x end)

    template =
      if Keyword.get(opts, :negative, false) do
        "did not increase by #{special_symbol}{{amount_change_up_required:human_readable}}"
      else
        "increased by #{special_symbol}{{amount_change_up:human_readable}}"
      end

    kv = %{
      amount_change_up: transform_fun.(amount_change),
      amount_change_up_required: transform_fun.(amount_up)
    }

    {template, kv}
  end

  # Amount
  def to_template_kv(%{absolute_change: value}, %{amount_down: _} = op, opts), do: to_template_kv(value, op, opts)

  def to_template_kv(amount_change, %{amount_down: amount_down}, opts) do
    special_symbol = Keyword.get(opts, :special_symbol, "")
    transform_fun = Keyword.get(opts, :value_transform, fn x -> x end)

    template =
      if Keyword.get(opts, :negative, false) do
        "did not decrease by #{special_symbol}{{amount_down_change_required:human_readable}}"
      else
        "decreased by #{special_symbol}{{amount_down_change:human_readable}}"
      end

    kv = %{
      amount_down_change: amount_change |> transform_fun.() |> abs(),
      amount_down_change_required: transform_fun.(amount_down)
    }

    {template, kv}
  end

  def to_template_kv(value, %{all_of: operations}, opts) when is_list(operations) do
    {template, kv} =
      Enum.reduce(operations, {[], %{}}, fn op, {template_acc, kv_acc} ->
        {template, kv} = to_template_kv(value, op, opts)

        {[template | template_acc], Map.merge(kv_acc, kv)}
      end)

    template = Enum.join(template, " and ")
    {template, kv}
  end

  def to_template_kv(value, %{none_of: operations}, opts) when is_list(operations) do
    opts = Keyword.put(opts, :negative, true)

    {template, kv} =
      Enum.reduce(operations, {[], %{}}, fn op, {template_acc, kv_acc} ->
        {template, kv} = to_template_kv(value, op, opts)

        {[template | template_acc], Map.merge(kv_acc, kv)}
      end)

    template = Enum.join(template, " and ")
    {template, kv}
  end

  def to_template_kv(value, %{some_of: operations}, opts) when is_list(operations) do
    {template, kv} =
      Enum.reduce(operations, {[], %{}}, fn op, {template_acc, kv_acc} ->
        if Sanbase.Alert.OperationEvaluation.operation_triggered?(value, op) do
          {template, kv} = to_template_kv(value, op, opts)
          {[template | template_acc], Map.merge(kv_acc, kv)}
        else
          {template_acc, kv_acc}
        end
      end)

    template = Enum.join(template, " and ")

    {template, kv}
  end

  def details(:metric, settings, _opts) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    before =
      settings.time_window
      |> Sanbase.DateTimeUtils.before_interval(now)
      |> DateTime.truncate(:second)

    {:ok, metric_metadata} = Sanbase.Metric.metadata(settings.metric)

    template =
      generated_by_data_template(
        "metric_data_from_human_readable",
        "metric_data_to_human_readable",
        :metric,
        metric_metadata.default_aggregation
      )

    kv = %{
      metric_data_from: before,
      metric_data_from_human_readable: Sanbase.DateTimeUtils.to_human_readable(before),
      metric_data_to: now,
      metric_data_to_human_readable: Sanbase.DateTimeUtils.to_human_readable(now),
      metric_data_aggregation: metric_metadata.default_aggregation
    }

    {template, kv}
  end

  def details(:signal, settings, _opts) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    before =
      settings.time_window
      |> Sanbase.DateTimeUtils.before_interval(now)
      |> DateTime.truncate(:second)

    {:ok, signal_metadata} = Sanbase.Signal.metadata(settings.signal)

    template =
      generated_by_data_template(
        "signal_data_from_human_readable",
        "signal_data_to_human_readable",
        :signal,
        signal_metadata.default_aggregation
      )

    kv = %{
      signal_data_from: before,
      signal_data_from_human_readable: Sanbase.DateTimeUtils.to_human_readable(before),
      signal_data_to: now,
      signal_data_to_human_readable: Sanbase.DateTimeUtils.to_human_readable(now),
      signal_data_aggregation: signal_metadata.default_aggregation
    }

    {template, kv}
  end

  def details(_, _, _), do: {"", %{}}

  # Private functions

  defp form_to_text(:singular), do: "is"
  defp form_to_text(:plural), do: "are"

  defp generated_by_data_template(_from_template, to_template, entity_type, :last) do
    """
    \\*_Generated by the value of the #{entity_type} at {{#{to_template}}}_
    """
  end

  defp generated_by_data_template(from_template, _to_template, entity_type, :first) do
    """
    \\*_Generated by the value of the #{entity_type} at {{#{from_template}}}_
    """
  end

  defp generated_by_data_template(from_template, to_template, entity_type, :sum) do
    """
    \\*_Generated by the sum of all #{entity_type} values in the interval:
    {{#{from_template}}} - {{#{to_template}}}_
    """
  end

  defp generated_by_data_template(from_template, to_template, entity_type, aggregation) do
    """
    \\*_Generated by the #{aggregation_to_str(aggregation)} value of the #{entity_type} in the interval:
    {{#{from_template}}} - {{#{to_template}}}_
    """
  end

  defp aggregation_to_str(:avg), do: "average"
  defp aggregation_to_str(aggregation), do: "#{aggregation}"
end
