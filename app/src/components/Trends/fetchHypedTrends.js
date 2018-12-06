import Raven from 'raven-js'
import { Observable } from 'rxjs'
import gql from 'graphql-tag'
import moment from 'moment'
import * as actions from './actions'

const trendingWordsGQL = gql`
  query trendingWords($from: DateTime!, $to: DateTime!, $hour: Int!) {
    trendingWords(source: ALL, size: 10, hour: $hour, from: $from, to: $to) {
      datetime
      topWords {
        score
        word
      }
    }
  }
`

const handleError = error => {
  Raven.captureException(error)
  return Observable.of({
    type: actions.TRENDS_HYPED_FETCH_FAILED,
    payload: error
  })
}

const secretDataTeamHours = [1, 8, 14]

export const fetchHypedTrends = (action$, store, { client }) =>
  action$.ofType(actions.TRENDS_HYPED_FETCH).exhaustMap(({ data = {} }) => {
    const startTime = Date.now()
    const queries = secretDataTeamHours.map(hour => {
      return client.query({
        query: trendingWordsGQL,
        variables: {
          hour,
          to: new Date().toISOString(),
          from: moment()
            .subtract(3, 'd')
            .toISOString()
        },
        context: { isRetriable: true }
      })
    })

    return Observable.forkJoin(queries)
      .delayWhen(() => Observable.timer(500 + startTime - Date.now()))
      .mergeMap(data => {
        const trends = data
          .reduce((acc, val, index) => {
            const { data = [] } = val
            data.trendingWords.forEach(el => {
              acc.push({
                ...el,
                datetime: moment(el.datetime)
                  .add(secretDataTeamHours[index], 'hours')
                  .utc()
                  .format()
              })
            })
            return acc
          }, [])
          .sort((a, b) => (moment(a.datetime).isAfter(b.datetime) ? 1 : -1))
          .reverse()
          .filter((_, index) => index < 3)
          .reverse()
        return Observable.of({
          type: actions.TRENDS_HYPED_FETCH_SUCCESS,
          payload: {
            items: trends,
            isLoading: false,
            error: false
          }
        })
      })
      .catch(handleError)
  })
