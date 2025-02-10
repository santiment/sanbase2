defmodule Sanbase.Timeline.Type do
  @moduledoc false
  @type event_type() :: String.t()
  @type autor_type() :: :all | :followed | :sanfam | :own
  @type filter() :: %{
          author: autor_type(),
          watchlists: list(non_neg_integer()),
          assets: list(String.t())
        }
  @type cursor_type() :: :before | :after
  @type cursor() :: %{type: cursor_type(), datetime: DateTime.t()}
  @type order() :: :datetime | :author | :votes | :comments
  @type timeline_event_args :: %{
          limit: non_neg_integer(),
          cursor: cursor(),
          filter_by: filter(),
          order_by: order()
        }
  @type events_with_cursor ::
          %{
            events: list(%Sanbase.Timeline.TimelineEvent{}),
            cursor: %{
              before: DateTime.t(),
              after: DateTime.t()
            }
          }
  @type fired_triggers_map :: %{
          user_trigger_id: non_neg_integer(),
          user_id: non_neg_integer(),
          payload: map(),
          triggered_at: DateTime.t()
        }
end
