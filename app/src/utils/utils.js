import sanitizeHtml from 'sanitize-html'

const findIndexByDatetime = (labels, datetime) => {
  return labels.findIndex(label => {
    return label.isSame(datetime)
  })
}

const calculateBTCVolume = ({volume, priceUsd, priceBtc}) => {
  return parseFloat(volume) / parseFloat(priceUsd) * parseFloat(priceBtc)
}

const calculateBTCMarketcap = ({marketcap, priceUsd, priceBtc}) => {
  return parseFloat(marketcap) / parseFloat(priceUsd) * parseFloat(priceBtc)
}

const getOrigin = () => {
  const origin = (window.env || {}).WEBSITE_URL || ''
  if (process.env.production) {
    return window.location.origin
  }
  return origin
}

const sanitizeMediumDraftHtml = (html) => sanitizeHtml(html,
  {
    allowedTags: [...sanitizeHtml.defaults.allowedTags, 'figure', 'figcaption', 'img'],
    allowedAttributes: {...sanitizeHtml.defaults.allowedAttributes, '*': ['class', 'id']}
  })

export {
  findIndexByDatetime,
  calculateBTCVolume,
  calculateBTCMarketcap,
  getOrigin,
  sanitizeMediumDraftHtml
}
