export const Sortable = {
  mounted() {
    const hook = this;
    
    new window.Sortable(this.el, {
      animation: 150,
      ghostClass: "bg-blue-100",
      onEnd: function(evt) {

        const ids = Array.from(hook.el.children).map(item => item.id);
        
        hook.pushEvent("reorder", { ids });
      }
    });
  }
};