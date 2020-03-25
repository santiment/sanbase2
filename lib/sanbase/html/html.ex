defmodule Sanbase.HTML do
  def truncate(text, max_words \\ 100) do
    tree =
      text
      |> Floki.parse_document!()
      |> Floki.HTMLTree.build()

    sorted_nodes = Enum.sort_by(tree.nodes, fn {k, _v} -> k end)

    truncated_nodes =
      sorted_nodes
      |> Enum.reduce_while({0, []}, fn {idx, node}, {words_acc, nodes_acc} ->
        case node do
          %Floki.HTMLTree.Text{content: content} ->
            node_words_count = calc_words(content)

            if words_acc + node_words_count > max_words do
              updated_node = %Floki.HTMLTree.Text{
                node
                | content: truncate_text(content, max_words - words_acc)
              }

              {:halt, {max_words, [{idx, updated_node} | nodes_acc]}}
            else
              {:cont, {words_acc + node_words_count, [{idx, node} | nodes_acc]}}
            end

          _ ->
            {:cont, {words_acc, [{idx, node} | nodes_acc]}}
        end
      end)
      |> elem(1)
      |> Enum.reverse()
      |> Enum.into(%{})

    updated_tree = %Floki.HTMLTree{
      node_ids: Map.keys(truncated_nodes),
      root_nodes_ids:
        Enum.filter(truncated_nodes, fn {_id, node} -> is_nil(node.parent_node_id) end)
        |> Enum.map(fn {k, _v} -> k end),
      nodes:
        truncated_nodes
        |> Enum.into(%{}, fn {k, node} ->
          node =
            case node do
              %Floki.HTMLTree.HTMLNode{children_nodes_ids: cni} ->
                new_cni =
                  MapSet.intersection(MapSet.new(cni), MapSet.new(Map.keys(truncated_nodes)))
                  |> MapSet.to_list()

                %Floki.HTMLTree.HTMLNode{node | children_nodes_ids: new_cni}

              _ ->
                node
            end

          {k, node}
        end)
    }

    updated_tree.root_nodes_ids
    |> Enum.map(fn id ->
      Floki.HTMLTree.to_tuple(updated_tree, Map.get(updated_tree.nodes, id))
    end)
    |> Floki.raw_html()
  end

  defp calc_words(text) do
    String.split(text, " ") |> length()
  end

  defp truncate_text(text, words) do
    String.split(text, " ")
    |> Enum.take(words)
    |> Enum.join(" ")
  end
end
