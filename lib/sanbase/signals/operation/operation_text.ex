defmodule Sanbase.Signal.OperationText do
  @moduledoc ~s"""
  A module providing a single function to_text/3 which transforms an operation
  to human readable text that can be included in the signal's payload
  """
  def to_text(value, operation, opts \\ [])

  # Above
  def to_text(%{current: value}, %{above: _} = op, opts), do: to_text(value, op, opts)

  def to_text(value, %{above: above}, opts) do
    form = Keyword.get(opts, :form, :singular)
    "#{form_to_text(form)} above #{above} and #{form_to_text(form)} now #{value}"
  end

  # Below
  def to_text(%{current: value}, %{below: _} = op, opts), do: to_text(value, op, opts)

  def to_text(value, %{below: below}, opts) do
    form = Keyword.get(opts, :form, :singular)

    "#{form_to_text(form)} below #{below} and #{form_to_text(form)} now #{value}"
  end

  # Inside channel
  def to_text(%{current: value}, %{inside_channel: _} = op, opts), do: to_text(value, op, opts)

  def to_text(value, %{inside_channel: [lower, upper]}, opts) do
    form = Keyword.get(opts, :form, :singular)

    "#{form_to_text(form)} inside the [#{lower}, #{upper}] interval and #{form_to_text(form)} now #{
      value
    }"
  end

  # Outside channel
  def to_text(%{current: value}, %{outside_channel: _} = op, opts), do: to_text(value, op, opts)

  def to_text(value, %{outside_channel: [lower, upper]}, opts) do
    form = Keyword.get(opts, :form, :singular)

    "#{form_to_text(form)} outside the [#{lower}, #{upper}] interval and #{form_to_text(form)} now #{
      value
    }"
  end

  # Percent up
  def to_text(%{percent_change: value}, %{percent_up: _} = op, opts), do: to_text(value, op, opts)

  def to_text(percent_change, %{percent_up: _percent}, _opts) do
    "increased by #{percent_change}%"
  end

  # Percent down
  def to_text(%{percent_change: value}, %{percent_down: _} = op, opts),
    do: to_text(value, op, opts)

  def to_text(percent_change, %{percent_down: _percent}, _opts) do
    "decreased by #{percent_change}%"
  end

  # Amount up
  def to_text(%{absolute_change: value}, %{amount_up: _} = op, opts), do: to_text(value, op, opts)

  def to_text(amount_changed, %{amount_up: _amount}, _opts) do
    "increased by #{amount_changed}"
  end

  # Amount
  def to_text(%{absolute_change: value}, %{amount_down: _} = op, opts),
    do: to_text(value, op, opts)

  def to_text(amount_changed, %{amount_down: _amount}, _opts) do
    "decreased by #{amount_changed}"
  end

  def to_text(_, %{all_of: operations}, _opts) when is_list(operations) do
    "not implemented"
  end

  def to_text(_, %{none_of: operations}, _opts) when is_list(operations) do
    "not implemented"
  end

  def to_text(_, %{some_of: operations}, _opts) when is_list(operations) do
    "not implemented"
  end

  # Private functions

  defp form_to_text(:singular), do: "is"
  defp form_to_text(:plural), do: "are"
end
