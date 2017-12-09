import Router from 'next/router'

exports.redirect_to = (res, location) => {
  if (res) {
    res.writeHead(301, { Location: location })
    res.end()
  } else {
    Router.replace(location)
  }
  return {}
}
