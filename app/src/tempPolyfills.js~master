// Why this was happened?
// https://dev.to/letsbsocial1/requestanimationframe--polyfill-in-react-16-2ce
// Dan Abramov approved this gist for JEST env.
const raf = (global.requestAnimationFrame = cb => {
  setTimeout(cb, 0)
})

export default raf
