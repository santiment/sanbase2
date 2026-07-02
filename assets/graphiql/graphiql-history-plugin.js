/**
 * Custom content for GraphiQL's built-in History plugin.
 *
 * Wraps the stock <History> list with a compact header whose Clear button
 * opens a confirmation dialog instead of instantly wiping history.
 * The stock header (with its one-click Clear) is hidden in graphiql.css.
 */
import React, { useState } from "react";
import { History, useHistory, useHistoryActions } from "@graphiql/plugin-history";
import { Dialog } from "@graphiql/react";
import { itemsToClear } from "./graphiql-history-utils.js";

export function SanHistory() {
  var items = useHistory();
  var actions = useHistoryActions();

  var _open = useState(false);
  var open = _open[0];
  var setOpen = _open[1];

  var clearable = itemsToClear(items);

  function confirmClear() {
    clearable.forEach(function (item) {
      actions.deleteFromHistory(item, true);
    });
    setOpen(false);
  }

  return React.createElement(
    "div",
    { className: "san-history" },
    React.createElement(
      "div",
      { className: "san-history-header" },
      "History",
      React.createElement(
        "button",
        {
          type: "button",
          className: "san-history-clear-btn",
          disabled: clearable.length === 0,
          onClick: function () { setOpen(true); },
        },
        "Clear"
      )
    ),
    React.createElement(
      Dialog,
      { open: open, onOpenChange: setOpen },
      React.createElement(
        "div",
        { className: "graphiql-dialog-header" },
        React.createElement(
          Dialog.Title,
          { className: "graphiql-dialog-title" },
          "Clear history?"
        )
      ),
      React.createElement(
        Dialog.Description,
        { className: "san-confirm-body" },
        "This removes all non-favorite queries from your history. " +
          "Favorites are kept. This cannot be undone."
      ),
      React.createElement(
        "div",
        { className: "san-confirm-footer" },
        React.createElement(
          "button",
          {
            type: "button",
            className: "san-confirm-cancel-btn",
            onClick: function () { setOpen(false); },
          },
          "Cancel"
        ),
        React.createElement(
          "button",
          {
            type: "button",
            className: "san-confirm-danger-btn",
            onClick: confirmClear,
          },
          "Clear history"
        )
      )
    ),
    React.createElement(History)
  );
}
