import moment from 'moment'
import outliers from 'outliers'

export const makeItervalBounds = interval => {
  switch (interval) {
    case '1d':
      return {
        from: moment().subtract(1, 'd').utc().format('YYYY-MM-DD') + 'T00:00:00Z',
        to: moment().utc().format(),
        minInterval: '5m'
      }
    case '1w':
      return {
        from: moment().subtract(1, 'weeks').utc().format(),
        to: moment().utc().format(),
        minInterval: '1h'
      }
    case '2w':
      return {
        from: moment().subtract(2, 'weeks').utc().format(),
        to: moment().utc().format(),
        minInterval: '1h'
      }
    default:
      return {
        from: moment().subtract(1, 'months').utc().format(),
        to: moment().utc().format(),
        minInterval: '1h'
      }
  }
}

export const normalizeData = ({
  data = [],
  fieldName,
  filter = 'all'
}) => {
  if (data.length === 0) { return [] }
  const normalizedData = data.map(el => {
    const normalizedField = parseFloat(el[`${fieldName}`])
    return {
      ...el,
      [fieldName]: normalizedField
    }
  })
  // https://github.com/matthewmueller/outliers/blob/9d9725ce75b55018a0b25f93d92538d7ff24b36c/index.js#L26
  // We use that lib, which helps find outliers. But if we want find rest we
  // need to do not very readable one liner.
  if (filter === 'only') {
    return normalizedData.filter((val, i, arr) =>
      !outliers(`${fieldName}`)(val, i, arr))
  }
  if (filter === 'rest') {
    return normalizedData.filter(outliers(`${fieldName}`))
  }
  return normalizedData
}
