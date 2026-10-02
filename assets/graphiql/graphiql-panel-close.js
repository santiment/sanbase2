/**
 * A "collapse" button at the top right of every side panel (History, Docs,
 * Explorer, Examples), so the panel can be closed without aiming for the
 * small active icon in the left sidebar.
 *
 * Rendered as an invisible child of <GraphiQL> and portalled into GraphiQL's
 * panel container. Closing presses the active sidebar button, so it behaves
 * exactly like clicking that icon (GraphiQL also collapses the panel's
 * resizable pane there, which is not reachable from outside).
 */
import React, { useLayoutEffect, useState } from "react";
import { createPortal } from "react-dom";
import { pick, useGraphiQL, ChevronLeftIcon } from "@graphiql/react";

var h = React.createElement;

function closePanel() {
  var active = document.querySelector("#graphiql .graphiql-sidebar button.active");
  if (active) active.click();
}

export function SanPanelClose() {
  var state = useGraphiQL(pick("visiblePlugin"));
  var plugin = state.visiblePlugin;
  var _container = useState(null);
  var container = _container[0];
  var setContainer = _container[1];

  // GraphiQL always renders the panel container; find it once mounted.
  useLayoutEffect(function () {
    setContainer(document.querySelector("#graphiql .graphiql-plugin"));
  }, []);

  if (!plugin || !container) return null;
  var label = "Hide " + plugin.title;
  return createPortal(
    h(
      "button",
      {
        type: "button",
        id: "san-panel-close",
        className: "san-panel-close",
        "aria-label": label,
        title: label,
        onClick: closePanel,
      },
      h(ChevronLeftIcon, { "aria-hidden": "true" })
    ),
    container
  );
}
