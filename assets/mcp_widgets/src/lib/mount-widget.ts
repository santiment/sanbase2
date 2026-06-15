import "san-webkit-next/app.css";
import { mount, type Component } from "svelte";

export function mountWidget(App: Component<any, any, any>) {
  const target = document.getElementById("root");
  if (!target) throw new Error("missing #root element in widget HTML");

  return mount(App, { target });
}
