export function websiteUrl () {
  if (typeof (window) !== 'undefined') {
    return '//' + window.location.host
  }

  return process.env.WEBSITE_URL || 'http://localhost:4000'
}
