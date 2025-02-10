defmodule Sanbase.HTML do
  @moduledoc """
  Module for html/text utility functions
  """

  alias Floki.HTMLTree.HTMLNode
  alias Floki.HTMLTree.Text

  @doc """
  Truncates html text to max_words by keeping the result html valid.
  """
  @spec truncate_html(String.t(), non_neg_integer()) :: String.t()
  def truncate_html(html, max_words \\ 100) do
    html
    |> build_floki_tree()
    |> truncate_nodes(max_words)
    |> update_tree()
    |> create_html_from_tree()
  end

  @spec calc_words(String.t()) :: non_neg_integer()
  def calc_words(text) do
    text
    |> String.split(" ", trim: true)
    |> Enum.reject(&(&1 == "\n"))
    |> length()
  end

  @doc """
  Truncate text to max words by preserving whitespace characters.
  """
  @spec truncate_text(String.t(), non_neg_integer()) :: String.t()
  def truncate_text(_, 0), do: ""

  def truncate_text(text, max_words) do
    text
    |> escape_whitespace_chars()
    |> String.split(" ")
    |> Enum.reduce_while({0, []}, fn word, {acc, words} ->
      cond do
        acc >= max_words -> {:halt, {acc, words}}
        word in ["\\n", "\\t", "\\r", "\\f", ""] -> {:cont, {acc, [word | words]}}
        true -> {:cont, {acc + 1, [word | words]}}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
    |> Enum.join(" ")
    |> unescape_whitespace_chars()
  end

  # helpers
  defp build_floki_tree(html) do
    html
    |> Floki.parse_document!()
    |> Floki.HTMLTree.build()
  end

  def truncate_nodes(tree, max_words) do
    tree.nodes
    |> Enum.sort_by(fn {k, _v} -> k end)
    |> Enum.reduce_while({0, []}, fn {idx, node}, {words_acc, nodes_acc} ->
      case node do
        %Text{content: _content} ->
          maybe_halt_if_max_words_reached(idx, node, words_acc, nodes_acc, max_words)

        _ ->
          {:cont, {words_acc, [{idx, node} | nodes_acc]}}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
    |> Map.new()
  end

  def update_tree(nodes) do
    node_ids = nodes |> Map.keys() |> Enum.reverse()

    root_nodes_ids =
      nodes
      |> Enum.filter(fn {_id, node} -> is_nil(node.parent_node_id) end)
      |> Enum.map(fn {k, _v} -> k end)
      |> Enum.sort()

    nodes =
      Map.new(nodes, fn {idx, node} ->
        node =
          case node do
            %HTMLNode{children_nodes_ids: children_nodes_ids} ->
              new_children_nodes_ids =
                children_nodes_ids |> intersection(node_ids) |> Enum.reverse()

              %HTMLNode{
                node
                | children_nodes_ids: new_children_nodes_ids
              }

            _ ->
              node
          end

        {idx, node}
      end)

    %Floki.HTMLTree{
      node_ids: node_ids,
      root_nodes_ids: root_nodes_ids,
      nodes: nodes
    }
  end

  defp create_html_from_tree(tree) do
    tree.root_nodes_ids
    |> Enum.map(fn id ->
      Floki.HTMLTree.to_tuple(tree, Map.get(tree.nodes, id))
    end)
    |> Floki.raw_html(encode: false)
  end

  defp maybe_halt_if_max_words_reached(idx, %Text{content: content} = node, words_acc, nodes_acc, max_words) do
    node_words_count = calc_words(content)

    if words_acc + node_words_count >= max_words do
      updated_node = %Text{
        node
        | content:
            truncate_text(
              content,
              max_words - words_acc
            )
      }

      {:halt, {max_words, [{idx, updated_node} | nodes_acc]}}
    else
      {:cont, {words_acc + node_words_count, [{idx, node} | nodes_acc]}}
    end
  end

  defp intersection(list1, list2) do
    list1
    |> MapSet.new()
    |> MapSet.intersection(MapSet.new(list2))
    |> MapSet.to_list()
  end

  defp escape_whitespace_chars(string) do
    string
    |> String.replace("\n", "\\n")
    |> String.replace("\t", "\\t")
    |> String.replace("\r", "\\r")
    |> String.replace("\f", "\\f")
  end

  defp unescape_whitespace_chars(string) do
    string
    |> String.replace("\\n", "\n")
    |> String.replace("\\t", "\t")
    |> String.replace("\\r", "\r")
    |> String.replace("\\f", "\f")
  end
end
