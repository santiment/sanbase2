export const Sortable = {
  mounted() {
    const hook = this;

    this._sortable = new window.Sortable(this.el, {
      animation: 150,
      ghostClass: "sortable-ghost-row",
      onEnd: function() {
        const ids = Array.from(hook.el.children).map(item => item.id);
        hook.pushEvent("reorder", { ids });
      }
    });
  },
  destroyed() {
    if (this._sortable) this._sortable.destroy();
  }
};