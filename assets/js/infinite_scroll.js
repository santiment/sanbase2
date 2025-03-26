export const InfiniteScroll = {
  mounted() {
    const observer = new IntersectionObserver(entries => {
      const entry = entries[0];
      if (entry.isIntersecting) {
        this.pushEvent('load_more');
      }
    }, {
      rootMargin: '200px',
    });

    observer.observe(this.el);
  },
  destroyed() {
    this.observer && this.observer.disconnect();
  }
}; 