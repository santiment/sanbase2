const handle = (cbk, online) => {
  if (window.requestAnimationFrame) {
    window.requestAnimationFrame(() => cbk({ online }))
  } else {
    setTimeout(() => cbk({ online }), 0)
  }
}

const detectNework = callback => {
  if (typeof window !== 'undefined' && window.addEventListener) {
    window.addEventListener('online', () => handle(callback, true))
    window.addEventListener('offline', () => handle(callback, false))
    handle(callback, window.navigator.onLine)
  }
}

export default detectNework
