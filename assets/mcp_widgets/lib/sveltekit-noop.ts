const noop = () => {};

export const page = { url: new URL(location.href) };

export {
  noop as goto,
  noop as beforeNavigate,
  noop as setUser,
  noop as captureException,
  noop as captureMessage,
  noop as init,
};
