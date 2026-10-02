/**
 * Toolbar buttons to make the editor text smaller / larger (query, response,
 * variables and headers editors), instead of zooming the whole page. The
 * size is a per-browser preference.
 */
import React, { useEffect, useState } from "react";
import { pick, useGraphiQL } from "@graphiql/react";
import { defaultStorage, readRaw, writeRaw } from "./graphiql-storage.js";

var h = React.createElement;

var STORAGE_KEY = "san-graphiql-font-size";
var DEFAULT_SIZE = 15; // GraphiQL's Monaco default
var MIN_SIZE = 10;
var MAX_SIZE = 28;

function clamp(size) {
  return Math.min(MAX_SIZE, Math.max(MIN_SIZE, size));
}

function readSize() {
  var v = parseInt(readRaw(defaultStorage(), STORAGE_KEY), 10);
  return Number.isFinite(v) ? clamp(v) : DEFAULT_SIZE;
}

function FontSizeButton(props) {
  return h(
    "button",
    {
      type: "button",
      className: "graphiql-toolbar-button san-font-size-btn",
      "aria-label": props.label,
      title: props.label,
      disabled: props.disabled,
      onClick: props.onClick,
    },
    h("span", { "aria-hidden": "true" }, "A", h("sub", null, props.sign))
  );
}

export function FontSizeButtons() {
  var editors = useGraphiQL(pick("queryEditor", "responseEditor", "variableEditor", "headerEditor"));
  var _size = useState(readSize);
  var size = _size[0];
  var setSize = _size[1];

  // Editors are created after the first render; apply whenever they appear.
  useEffect(function () {
    [editors.queryEditor, editors.responseEditor, editors.variableEditor, editors.headerEditor]
      .forEach(function (editor) {
        if (editor) editor.updateOptions({ fontSize: size });
      });
  }, [size, editors.queryEditor, editors.responseEditor, editors.variableEditor, editors.headerEditor]);

  function change(delta) {
    var next = clamp(size + delta);
    setSize(next);
    writeRaw(defaultStorage(), STORAGE_KEY, String(next));
  }

  return h(
    React.Fragment,
    null,
    h(FontSizeButton, {
      label: "Smaller editor text (" + size + "px)",
      sign: "−",
      disabled: size <= MIN_SIZE,
      onClick: function () { change(-1); },
    }),
    h(FontSizeButton, {
      label: "Larger editor text (" + size + "px)",
      sign: "+",
      disabled: size >= MAX_SIZE,
      onClick: function () { change(1); },
    })
  );
}
