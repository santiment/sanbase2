defmodule Sanbase.Signal.OperationText.KV do
  @moduledoc ~s"""
  A module providing a single function to_template_kv/3 which transforms an operation
  to human readable text that can be included in the signal's payload
  """

  def current_value(%{current: value, previous: previous}, opts) do
    special_symbol = Keyword.get(opts, :special_symbol, "")
    transform_fun = Keyword.get(opts, :value_transform, fn x -> x end)

    template = "was: #{special_symbol}{{previous}}, now: #{special_symbol}{{value}}"

    kv = %{
      value: transform_fun.(value),
      previous: transform_fun.(previous),
      human_readable: [:value, :previous]
    }

    {template, kv}
  end

  def current_value(%{current: value}, opts) do
    special_symbol = Keyword.get(opts, :special_symbol, "")
    transform_fun = Keyword.get(opts, :value_transform, fn x -> x end)

    template = "now: #{special_symbol}{{value}}"
    kv = %{value: transform_fun.(value), human_readable: [:value]}
    {template, kv}
  end

  def to_template_kv(value, operation, opts \\ [])

  # Above
  def to_template_kv(%{current: value}, %{above: _} = op, opts),
    do: to_template_kv(value, op, opts)

  def to_template_kv(value, %{above: above}, opts) do
    form = Keyword.get(opts, :form, :singular) |> form_to_text()
    special_symbol = Keyword.get(opts, :special_symbol, "")
    transform_fun = Keyword.get(opts, :value_transform, fn x -> x end)

    template =
      case Keyword.get(opts, :negative, false) do
        true -> "#{form} not above #{special_symbol}{{above}}"
        false -> "#{form} above #{special_symbol}{{above}}"
      end

    kv = %{
      above: transform_fun.(above),
      value: transform_fun.(value),
      human_readable: [:above, :value]
    }

    {template, kv}
  end

  # Below
  def to_template_kv(%{current: value}, %{below: _} = op, opts),
    do: to_template_kv(value, op, opts)

  def to_template_kv(value, %{below: below}, opts) do
    form = Keyword.get(opts, :form, :singular) |> form_to_text()
    special_symbol = Keyword.get(opts, :special_symbol, "")
    transform_fun = Keyword.get(opts, :value_transform, fn x -> x end)

    template =
      case Keyword.get(opts, :negative, false) do
        true -> "#{form} not below #{special_symbol}{{below}}"
        false -> "#{form} below #{special_symbol}{{below}}"
      end

    kv = %{
      below: transform_fun.(below),
      value: transform_fun.(value),
      human_readable: [:below, :value]
    }

    {template, kv}
  end

  # Inside channel
  def to_template_kv(%{current: value}, %{inside_channel: _} = op, opts),
    do: to_template_kv(value, op, opts)

  def to_template_kv(value, %{inside_channel: [lower, upper]}, opts) do
    form = Keyword.get(opts, :form, :singular) |> form_to_text()
    special_symbol = Keyword.get(opts, :special_symbol, "")
    transform_fun = Keyword.get(opts, :value_transform, fn x -> x end)

    template =
      case Keyword.get(opts, :negative, false) do
        true ->
          "#{form} not inside the [#{special_symbol}{{lower}}, #{special_symbol}{{upper}}] interval"

        false ->
          "#{form} inside the [#{special_symbol}{{lower}}, #{special_symbol}{{upper}}] interval"
      end

    kv = %{
      lower: transform_fun.(lower),
      upper: transform_fun.(upper),
      value: transform_fun.(value),
      human_readable: [:lower, :upper, :value]
    }

    {template, kv}
  end

  # Outside channel
  def to_template_kv(%{current: value}, %{outside_channel: _} = op, opts),
    do: to_template_kv(value, op, opts)

  def to_template_kv(value, %{outside_channel: [lower, upper]}, opts) do
    form = Keyword.get(opts, :form, :singular) |> form_to_text()
    special_symbol = Keyword.get(opts, :special_symbol, "")
    transform_fun = Keyword.get(opts, :value_transform, fn x -> x end)

    template =
      case Keyword.get(opts, :negative, false) do
        true ->
          "#{form} not outside the [#{special_symbol}{{lower}}, #{special_symbol}{{upper}}] interval"

        false ->
          "#{form} outside the [#{special_symbol}{{lower}}, #{special_symbol}{{upper}}] interval"
      end

    kv = %{
      lower: transform_fun.(lower),
      upper: transform_fun.(upper),
      value: transform_fun.(value),
      human_readable: [:lower, :upper, :value]
    }

    {template, kv}
  end

  # Percent up
  def to_template_kv(%{percent_change: value}, %{percent_up: _} = op, opts),
    do: to_template_kv(value, op, opts)

  def to_template_kv(percent_change, %{percent_up: percent_up}, opts) do
    transform_fun = Keyword.get(opts, :value_transform, fn x -> x end)

    template =
      case Keyword.get(opts, :negative, false) do
        true -> "did not increase by {{percent_up_required}}%"
        false -> "increased by {{percent_up}}%"
      end

    kv = %{
      percent_up: transform_fun.(percent_change),
      percent_up_required: transform_fun.(percent_up)
    }

    {template, kv}
  end

  # Percent down
  def to_template_kv(%{percent_change: value}, %{percent_down: _} = op, opts),
    do: to_template_kv(value, op, opts)

  def to_template_kv(percent_change, %{percent_down: percent_down}, opts) do
    transform_fun = Keyword.get(opts, :value_transform, fn x -> x end)

    template =
      case Keyword.get(opts, :negative, false) do
        true -> "did not decrease by {{percent_down_required}}%"
        false -> "decreased by {{percent_down}}%"
      end

    kv = %{
      percent_down: transform_fun.(percent_change) |> abs(),
      percent_down_required: transform_fun.(percent_down)
    }

    {template, kv}
  end

  # Amount up
  def to_template_kv(%{absolute_change: value}, %{amount_up: _} = op, opts),
    do: to_template_kv(value, op, opts)

  def to_template_kv(amount_change, %{amount_up: amount_up}, opts) do
    special_symbol = Keyword.get(opts, :special_symbol, "")
    transform_fun = Keyword.get(opts, :value_transform, fn x -> x end)

    template =
      case Keyword.get(opts, :negative, false) do
        true -> "did not increase by #{special_symbol}{{amount_change_up_required}}"
        false -> "increased by #{special_symbol}{{amount_change_up}}"
      end

    kv = %{
      amount_change_up: transform_fun.(amount_change),
      amount_change_up_required: transform_fun.(amount_up),
      human_readable: [:amount_change_up, :amount_change_up_required]
    }

    {template, kv}
  end

  # Amount
  def to_template_kv(%{absolute_change: value}, %{amount_down: _} = op, opts),
    do: to_template_kv(value, op, opts)

  def to_template_kv(amount_change, %{amount_down: amount_down}, opts) do
    special_symbol = Keyword.get(opts, :special_symbol, "")
    transform_fun = Keyword.get(opts, :value_transform, fn x -> x end)

    template =
      case Keyword.get(opts, :negative, false) do
        true -> "did not decrease by #{special_symbol}{{amount_down_change_required}}"
        false -> "decreased by #{special_symbol}{{amount_down_change}}"
      end

    kv = %{
      amount_down_change: transform_fun.(amount_change) |> abs(),
      amount_down_change_required: transform_fun.(amount_down),
      human_readable: [:amount_down_change, :amount_down_change_required]
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
        if Sanbase.Signal.OperationEvaluation.operation_triggered?(value, op) do
          {template, kv} = to_template_kv(value, op, opts)
          {[template | template_acc], Map.merge(kv_acc, kv)}
        else
          {template_acc, kv_acc}
        end
      end)

    template = template |> Enum.join(" and ")

    {template, kv}
  end

  def details(:metric, settings, _opts) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    before =
      Sanbase.DateTimeUtils.before_interval(settings.time_window, now)
      |> DateTime.truncate(:second)

    {:ok, metric_metadata} = Sanbase.Metric.metadata(settings.metric)

    template =
      generated_by_data_template(
        "metric_data_from_human_readable",
        "metric_data_to_human_readable",
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

  def details(_, _, _), do: {"", %{}}

  # Private functions

  defp form_to_text(:singular), do: "is"
  defp form_to_text(:plural), do: "are"

  defp generated_by_data_template(_from_template, to_template, :last) do
    """
    Generated by the value of the metric at {{#{to_template}}}
    """
  end

  defp generated_by_data_template(from_template, _to_template, :first) do
    """
    Generated by the value of the metric at {{#{from_template}}}
    """
  end

  defp generated_by_data_template(from_template, to_template, :sum) do
    """
    Generated by the sum of all metric values in the interval:
    {{#{from_template}}} - {{#{to_template}}}
    """
  end

  defp generated_by_data_template(from_template, to_template, aggregation) do
    """
    Generated by the #{aggregation_to_str(aggregation)} value of the metric in the interval:
    {{#{from_template}}} - {{#{to_template}}}
    """
  end

  defp aggregation_to_str(:avg), do: "average"
  defp aggregation_to_str(aggregation), do: "#{aggregation}"
end
