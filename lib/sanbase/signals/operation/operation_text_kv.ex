defmodule Sanbase.Signal.OperationText.KV do
  @moduledoc ~s"""
  A module providing a single function to_template_kv/3 which transforms an operation
  to human readable text that can be included in the signal's payload
  """

  def current_value(%{current: value}, _, opts) do
    form = Keyword.get(opts, :form, :singular) |> form_to_text()
    template = "#{form} now {{value}}"
    kv = %{value: value}
    {template, kv}
  end

  def to_template_kv(value, operation, opts \\ [])

  # Above
  def to_template_kv(%{current: value}, %{above: _} = op, opts),
    do: to_template_kv(value, op, opts)

  def to_template_kv(value, %{above: above}, opts) do
    form = Keyword.get(opts, :form, :singular) |> form_to_text()

    template =
      case Keyword.get(opts, :negative, false) do
        true -> "#{form} not above {{above}}"
        false -> "#{form} above {{above}}"
      end

    kv = %{above: above, value: value}
    {template, kv}
  end

  # Below
  def to_template_kv(%{current: value}, %{below: _} = op, opts),
    do: to_template_kv(value, op, opts)

  def to_template_kv(value, %{below: below}, opts) do
    form = Keyword.get(opts, :form, :singular) |> form_to_text()

    template =
      case Keyword.get(opts, :negative, false) do
        true -> "#{form} not below {{below}}"
        false -> "#{form} below {{below}}"
      end

    kv = %{below: below, value: value}
    {template, kv}
  end

  # Inside channel
  def to_template_kv(%{current: value}, %{inside_channel: _} = op, opts),
    do: to_template_kv(value, op, opts)

  def to_template_kv(value, %{inside_channel: [lower, upper]}, opts) do
    form = Keyword.get(opts, :form, :singular) |> form_to_text()

    template =
      case Keyword.get(opts, :negative, false) do
        true -> "#{form} not inside the [{{lower}}, {{upper}}] interval"
        false -> "#{form} inside the [{{lower}}, {{upper}}] interval"
      end

    kv = %{lower: lower, upper: upper, value: value}
    {template, kv}
  end

  # Outside channel
  def to_template_kv(%{current: value}, %{outside_channel: _} = op, opts),
    do: to_template_kv(value, op, opts)

  def to_template_kv(value, %{outside_channel: [lower, upper]}, opts) do
    form = Keyword.get(opts, :form, :singular) |> form_to_text()

    template =
      case Keyword.get(opts, :negative, false) do
        true -> "#{form} not outside the [{{lower}}, {{upper}}] interval"
        false -> "#{form} outside the [{{lower}}, {{upper}}] interval"
      end

    kv = %{lower: lower, upper: upper, value: value}
    {template, kv}
  end

  # Percent up
  def to_template_kv(%{percent_change: value}, %{percent_up: _} = op, opts),
    do: to_template_kv(value, op, opts)

  def to_template_kv(percent_change, %{percent_up: percent_up}, opts) do
    template =
      case Keyword.get(opts, :negative, false) do
        true -> "did not increase by {{percent_up_required}}%"
        false -> "increased by {{percent_up}}%"
      end

    kv = %{percent_up: percent_change, percent_up_required: percent_up}
    {template, kv}
  end

  # Percent down
  def to_template_kv(%{percent_change: value}, %{percent_down: _} = op, opts),
    do: to_template_kv(value, op, opts)

  def to_template_kv(percent_change, %{percent_down: percent_down}, opts) do
    template =
      case Keyword.get(opts, :negative, false) do
        true -> "did not decrease by {{percent_down_required}}%"
        false -> "decreased by {{percent_down}}%"
      end

    kv = %{percent_down: abs(percent_change), percent_down_required: percent_down}
    {template, kv}
  end

  # Amount up
  def to_template_kv(%{absolute_change: value}, %{amount_up: _} = op, opts),
    do: to_template_kv(value, op, opts)

  def to_template_kv(amount_change, %{amount_up: amount_up}, opts) do
    template =
      case Keyword.get(opts, :negative, false) do
        true -> "did not increase by {{amount_change_up_required}}"
        false -> "increased by {{amount_change_up}}"
      end

    kv = %{amount_change_up: amount_change, amount_change_up_required: amount_up}
    {template, kv}
  end

  # Amount
  def to_template_kv(%{absolute_change: value}, %{amount_down: amount_down} = op, opts),
    do: to_template_kv(value, op, opts)

  def to_template_kv(amount_change, %{amount_down: amount_down}, opts) do
    template =
      case Keyword.get(opts, :negative, false) do
        true -> "did not decrease by {{amount_down_change_required}}"
        false -> "decreased by {{amount_down_change}}"
      end

    kv = %{amount_down_change: abs(amount_change), amount_down_change_required: amount_down}
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

  # Private functions

  defp form_to_text(:singular), do: "is"
  defp form_to_text(:plural), do: "are"
end
