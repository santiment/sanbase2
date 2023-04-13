defmodule Sanbase.Alert.ResultBuilder do
  @moduledoc """
  Help determine if an alert should be triggered
  """

  import Sanbase.Alert.OperationEvaluation
  alias Sanbase.Alert.ResultBuilder.Transformer

  @trigger_modules Sanbase.Alert.List.get()

  @doc ~s"""
  Determine by the provided data and alert settings if the alert should fire.

  This function is called when the standard alert data configuration is used. This
  means that we have float values for two points in time - now and a past value.
  Based on those values we can compute percent change, absolute value change,
  threshold checks, etc. Example for such operation is: Price increased by 10%
  since 1 day ago. Provided the raw data and the settings, the function returns
  the trigger settings with updated `triggered?` and `template_kv` fields. These
  fields are updated by computing whether or not the alert should be triggered.

  The `data` argument is in the format expected by the
  Sanbase.Alert.ResultBuilder.Transformer.transform/2 function. By default, data
  is a list of 2-element tuples where the first elemenet is a string identifier
  (slug) and the second element is a list of maps with the `value` key. If the key
  is not `value`, but something else, this has to be specified as the `value_key`
  key in the opts.
  """
  @spec build(
          data :: list({identifier, list()}),
          settings :: settings,
          template_kv_fun :: (map(), settings -> {String.t(), map()}),
          opts :: Keyword.t()
        ) :: settings
        when settings: map(), identifier: any()
  def build(
        data,
        %trigger_module{operation: operation} = settings,
        template_kv_fun,
        opts \\ []
      )
      when trigger_module in @trigger_modules and is_function(template_kv_fun, 2) do
    template_kv =
      Transformer.transform(data, Keyword.get(opts, :value_key, :value))
      |> Enum.reduce(%{}, fn %{} = transformed_data, acc ->
        case operation_triggered?(transformed_data, operation) do
          true ->
            Map.put(
              acc,
              transformed_data.identifier,
              template_kv_fun.(transformed_data, settings)
            )

          false ->
            acc
        end
      end)

    %{
      settings
      | triggered?: template_kv != %{},
        template_kv: template_kv
    }
  end

  @doc ~s"""
  Determine by the provided data and alert settings if the alert should fire.

  This function is called when the alert is fired based on the additional/removal
  of some items from a list that is computed. For example this is used when firing
  alerts when a new asset is added to an address or when an asset is removed from it.

  Provided the current list the settings that hold the previous known state, the
  function returns the trigger settings with updated `triggered?` and
  `template_kv` fields. These fields are updated by computing whether or not the
  alert should be triggered.

  The `data` argument is in the format expected by the
  Sanbase.Alert.ResultBuilder.Transformer.transform/2 function. By default, data
  is a list of 2-element tuples where the first elemenet is a string identifier
  (slug) and the second element is a list of maps with the `value` key. If the key
  is not `value`, but something else, this has to be specified as the `value_key`
  key in the opts.
  """
  @spec build_state_difference(
          data :: list({identifier, list()}) | list(String.t()),
          settings :: settings,
          template_kv_fun :: (map(), settings -> {String.t(), map()}),
          opts :: Keyword.t()
        ) :: settings
        when settings: map(), identifier: any()
  def build_state_difference(
        [str | _] = current_list,
        %trigger_module{} = settings,
        template_kv_fun,
        opts
      )
      when trigger_module in @trigger_modules and is_function(template_kv_fun, 2) and
             is_binary(str) do
    state_list_key = Keyword.fetch!(opts, :state_list_key)
    added_items_key = Keyword.fetch!(opts, :added_items_key)
    removed_items_key = Keyword.fetch!(opts, :removed_items_key)

    previous_list = Map.get(settings.state, state_list_key, [])

    added_items = (current_list -- previous_list) |> Enum.reject(&is_nil/1)
    removed_items = (previous_list -- current_list) |> Enum.reject(&is_nil/1)

    case added_items != [] or removed_items != [] do
      true ->
        template_kv =
          template_kv_fun.(
            %{added_items_key => added_items, removed_items_key => removed_items},
            settings
          )

        %{
          settings
          | template_kv: %{"default" => template_kv},
            state: %{state_list_key => current_list},
            triggered?: true
        }

      false ->
        %{settings | triggered?: false}
    end
  end

  def build_state_difference(
        [tuple | _] = current_data,
        %trigger_module{} = settings,
        template_kv_fun,
        opts
      )
      when trigger_module in @trigger_modules and is_function(template_kv_fun, 2) and
             is_tuple(tuple) do
    state_list_key = Keyword.fetch!(opts, :state_list_key)
    added_items_key = Keyword.fetch!(opts, :added_items_key)
    removed_items_key = Keyword.fetch!(opts, :removed_items_key)

    # TODO: Take a look at this. Sometimes it's a list, sometimes it's a map
    previous_map = Map.get(settings.state, state_list_key, %{})

    template_kv =
      Enum.reduce(current_data, %{}, fn {identifier, current_list}, acc ->
        previous_list = Map.get(previous_map, identifier, [])

        added_items = (current_list -- previous_list) |> Enum.reject(&is_nil/1)
        removed_items = (previous_list -- current_list) |> Enum.reject(&is_nil/1)

        case added_items != [] or removed_items != [] do
          true ->
            template_kv =
              template_kv_fun.(
                %{added_items_key => added_items, removed_items_key => removed_items},
                settings
              )

            Map.put(acc, identifier, template_kv)

          false ->
            acc
        end
      end)

    %{
      settings
      | triggered?: template_kv != %{},
        template_kv: template_kv
    }
  end

  @doc ~s"""
  Return a string containing the formatted entering (newcommrs)
  and exiting (leavers) projects
  """
  @spec build_enter_exit_projects_str(list(String.t()), list(String.t())) :: String.t()
  def build_enter_exit_projects_str(added_slugs, removed_slugs) do
    projects_map =
      Sanbase.Project.List.by_slugs(added_slugs ++ removed_slugs, preload?: false)
      |> Enum.into(%{}, fn %{slug: slug} = project -> {slug, project} end)

    newcomers = slugs_to_projects_string_list(added_slugs, projects_map)
    leavers = slugs_to_projects_string_list(removed_slugs, projects_map)

    """
    #{length(newcomers)} Newcomers:
    #{newcomers |> Enum.join("\n")}
    ---
    #{length(leavers)} Leavers:
    #{leavers |> Enum.join("\n")}
    """
  end

  defp slugs_to_projects_string_list(slugs, projects_map) do
    slugs
    |> Enum.map(&Map.get(projects_map, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&"[##{&1.ticker} | #{&1.name}](#{Sanbase.Project.sanbase_link(&1)})")
  end
end
