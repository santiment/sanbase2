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
  if (process.env.NODE_ENV === 'development') {
    return process.env.REACT_APP_WEBSITE_URL || window.location.origin
  }
  return (window.env || {}).WEBSITE_URL ||
    process.env.REACT_APP_WEBSITE_URL ||
    window.location.origin
}

const sanitizeMediumDraftHtml = (html) => sanitizeHtml(html,
  {
    allowedTags: [...sanitizeHtml.defaults.allowedTags, 'figure', 'figcaption', 'img'],
    allowedAttributes: {...sanitizeHtml.defaults.allowedAttributes, '*': ['class', 'id']}
  })

const filterProjectsByMarketSegment = (projects, categories, allMarketSegments) => {
  if (projects === undefined || Object.keys(categories).length === 0) {
    return projects
  }

  return projects.filter((project) =>
    Object.keys(categories).includes(Object.keys(allMarketSegments).find(key =>
      allMarketSegments[key] === project.marketSegment
    )
  ))
}

export {
  findIndexByDatetime,
  calculateBTCVolume,
  calculateBTCMarketcap,
  getOrigin,
  sanitizeMediumDraftHtml,
  filterProjectsByMarketSegment
}
