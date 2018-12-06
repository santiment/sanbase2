import sanitizeHtml from 'sanitize-html'
import moment from 'moment'
import ms from 'ms'

const findIndexByDatetime = (labels, datetime) => {
  return labels.findIndex(label => {
    return label.isSame(datetime)
  })
}

const calculateBTCVolume = ({ volume, priceUsd, priceBtc }) => {
  return (parseFloat(volume) / parseFloat(priceUsd)) * parseFloat(priceBtc)
}

const calculateBTCMarketcap = ({ marketcap, priceUsd, priceBtc }) => {
  return (parseFloat(marketcap) / parseFloat(priceUsd)) * parseFloat(priceBtc)
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

const getConsentUrl = () => {
  if (process.env.NODE_ENV === 'development') {
    return process.env.REACT_APP_BACKEND_URL || window.location.origin
  }
  return (
    (window.env || {}).LOGIN_URL ||
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

const getStartOfTheDay = () => {
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  return today.toISOString()
}

const getYesterday = () => {
  const yesterday = new Date(Date.now() - 86400000)
  yesterday.setHours(0, 0, 0, 0)
  return yesterday.toISOString()
}

const mergeTimeseriesByKey = ({ timeseries, key }) => {
  const longestTS = timeseries.reduce((acc, val) => {
    return acc.length > val.length ? acc : val
  }, [])
  return longestTS.map(data => {
    return timeseries.reduce(
      (acc, val) => {
        return {
          ...acc,
          ...val.find(data2 => data2[key] === data[key])
        }
      },
      {
        ...data
      }
    )
  })
}

const getTimeFromFromString = (time = '1y') => {
  if (isNaN(new Date(time).getDate())) {
    const timeExpression = time.replace(/\d/g, '')
    const multiplier = time.replace(/[a-zA-Z]+/g, '') || 1
    let diff = 0
    if (timeExpression === 'all') {
      diff = 2 * 12 * 30 * 24 * 60 * 60 * 1000
    } else if (timeExpression === 'm') {
      diff = multiplier * 30 * 24 * 60 * 60 * 1000
    } else if (timeExpression === 'w') {
      diff = multiplier * 7 * 24 * 60 * 60 * 1000
    } else {
      diff = ms(time)
    }
    return new Date(+new Date() - diff).toISOString()
  }
  return time
}

const capitalizeStr = string => string.charAt(0).toUpperCase() + string.slice(1)

/* UTILS METHOD  */
// Escaping for corrent alias syntax
// Otherwise: GraphQLError: Syntax Error GraphQL request (16:7) Expected Name, found Int "0" - for 0x
// bitcoin-cash | ab-chain-rtb = Syntax Error GraphQL request (4:15) Invalid number, expected digit but got: "c"
const getEscapedGQLFieldAlias = fieldName => '_' + fieldName.replace(/-/g, '')

export {
  findIndexByDatetime,
  calculateBTCVolume,
  calculateBTCMarketcap,
  getOrigin,
  getAPIUrl,
  getConsentUrl,
  sanitizeMediumDraftHtml,
  filterProjectsByMarketSegment,
  binarySearchHistoryPriceIndex,
  getStartOfTheDay,
  getYesterday,
  mergeTimeseriesByKey,
  getTimeFromFromString,
  capitalizeStr,
  getEscapedGQLFieldAlias
}
