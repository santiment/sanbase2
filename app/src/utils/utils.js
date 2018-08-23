import sanitizeHtml from 'sanitize-html'
import moment from 'moment'

const findIndexByDatetime = (labels, datetime) => {
  return labels.findIndex(label => {
    return label.isSame(datetime)
  })
}

const calculateBTCVolume = ({ volume, priceUsd, priceBtc }) => {
  return parseFloat(volume) / parseFloat(priceUsd) * parseFloat(priceBtc)
}

const calculateBTCMarketcap = ({ marketcap, priceUsd, priceBtc }) => {
  return parseFloat(marketcap) / parseFloat(priceUsd) * parseFloat(priceBtc)
}

const getOrigin = () => {
  if (process.env.NODE_ENV === 'development') {
    return process.env.REACT_APP_FRONTEND_URL || window.location.origin
  }
  return (
    (window.env || {}).FRONTEND_URL ||
    process.env.REACT_APP_FRONTEND_URL ||
    window.location.origin
  )
}

const getAPIUrl = () => {
  if (process.env.NODE_ENV === 'development') {
    return process.env.REACT_APP_BACKEND_URL || window.location.origin
  }
  return (
    (window.env || {}).BACKEND_URL ||
    process.env.REACT_APP_BACKEND_URL ||
    window.location.origin
  )
}

const sanitizeMediumDraftHtml = html =>
  sanitizeHtml(html, {
    allowedTags: [
      ...sanitizeHtml.defaults.allowedTags,
      'figure',
      'figcaption',
      'img'
    ],
    allowedAttributes: {
      ...sanitizeHtml.defaults.allowedAttributes,
      '*': ['class', 'id']
    }
  })

const filterProjectsByMarketSegment = (projects, categories) => {
  if (projects === undefined || Object.keys(categories).length === 0) {
    return projects
  }

  return projects.filter(project =>
    Object.keys(categories).includes(project.marketSegment)
  )
}

const binarySearchDirection = {
  MOVE_STOP_TO_LEFT: -1,
  MOVE_START_TO_RIGHT: 1
}

const isCurrentDatetimeBeforeTarget = (current, target) =>
  moment(current.datetime).isBefore(moment(target))

const binarySearchHistoryPriceIndex = (history, targetDatetime) => {
  let start = 0
  let stop = history.length - 1
  let middle = Math.floor((start + stop) / 2)
  while (start < stop) {
    const searchResult = isCurrentDatetimeBeforeTarget(
      history[middle],
      targetDatetime
    )
      ? binarySearchDirection.MOVE_START_TO_RIGHT
      : binarySearchDirection.MOVE_STOP_TO_LEFT

    if (searchResult === binarySearchDirection.MOVE_START_TO_RIGHT) {
      start = middle + 1
    } else {
      stop = middle - 1
    }

    middle = Math.floor((start + stop) / 2)
  }
  // Correcting the result to the first data of post's creation date
  while (!isCurrentDatetimeBeforeTarget(history[middle], targetDatetime)) {
    middle--
  }

  return middle
}

export {
  findIndexByDatetime,
  calculateBTCVolume,
  calculateBTCMarketcap,
  getOrigin,
  getAPIUrl,
  sanitizeMediumDraftHtml,
  filterProjectsByMarketSegment,
  binarySearchHistoryPriceIndex
}
