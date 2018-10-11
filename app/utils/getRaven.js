import Raven from 'raven-js'

const getRaven = () => {
  if (!window.env) {
    window.env = {
      RAVEN_DSN: '',
      WEBSITE_URL: process.env.REACT_APP_WEBSITE_URL || ''
    }
  }
  Raven.config(window.env.RAVEN_DSN || '', {
    release: process.env.REACT_APP_VERSION,
    environment: process.env.NODE_ENV,
    tags: {
      git_commit: process.env.REACT_APP_VERSION.split('-')[1]
    }
  }).install()
  return Raven
}

export default getRaven
