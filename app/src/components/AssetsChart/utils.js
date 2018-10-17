import moment from 'moment'

export const makeIntervalBounds = interval => {
  switch (interval) {
    case '1d':
      return {
        from:
          moment()
            .subtract(1, 'd')
            .utc()
            .format('YYYY-MM-DD') + 'T00:00:00Z',
        to: moment()
          .utc()
          .format(),
        minInterval: '5m'
      }
    case '1w':
      return {
        from: moment()
          .subtract(1, 'weeks')
          .utc()
          .format(),
        to: moment()
          .utc()
          .format(),
        minInterval: '1h'
      }
    case '2w':
      return {
        from: moment()
          .subtract(2, 'weeks')
          .utc()
          .format(),
        to: moment()
          .utc()
          .format(),
        minInterval: '1h'
      }
    case '3m':
      return {
        from: moment()
          .subtract(3, 'months')
          .utc()
          .format(),
        to: moment()
          .utc()
          .format(),
        minInterval: '1d'
      }
    case 'all':
      return {
        from: moment()
          .subtract(2, 'years')
          .utc()
          .format(),
        to: moment()
          .utc()
          .format(),
        minInterval: '1d'
      }
    default:
      return {
        from: moment()
          .subtract(1, 'months')
          .utc()
          .format(),
        to: moment()
          .utc()
          .format(),
        minInterval: '1h'
      }
  }
}
