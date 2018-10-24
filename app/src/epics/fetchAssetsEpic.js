import Raven from 'raven-js'
import { Observable } from 'rxjs'
import { projectBySlugGQL } from './../pages/Projects/allProjectsGQL'
import {
  WatchlistGQL,
  publicWatchlistGQL
} from './../components/WatchlistPopup/WatchlistGQL.js'
import {
  allProjectsGQL,
  allErc20ProjectsGQL,
  currenciesGQL
} from './../pages/Projects/allProjectsGQL'
import * as actions from './../actions/types'

const handleError = error => {
  Raven.captureException(error)
  return Observable.of({
    type: actions.ASSETS_FETCH_FAILED,
    payload: error
  })
}

const fetchAssets$ = ({ type = 'all', client }) => {
  return Observable.of(type).switchMap(type =>
    client.query({
      query: pickProjectsType(type).gql,
      context: { isRetriable: true }
    })
  )
}

const pickProjectsType = type => {
  switch (type) {
    case 'all':
      return {
        projects: 'allProjects',
        gql: allProjectsGQL
      }
    case 'currency':
      return {
        projects: 'allCurrencyProjects',
        gql: currenciesGQL
      }
    case 'erc20':
      return {
        projects: 'allErc20Projects',
        gql: allErc20ProjectsGQL
      }
    default:
      return {
        projects: 'allProjects',
        gql: allProjectsGQL
      }
  }
}

const mapDataToAssets = ({ type, data }) => {
  const { loading, error } = data
  const items = !data.error ? data.data[pickProjectsType(type).projects] : []
  const isEmpty = items && items.length === 0
  return {
    isLoading: loading,
    isEmpty,
    items,
    error
  }
}

export const fetchAssetsEpic = (action$, store, { client }) =>
  action$
    .ofType(actions.ASSETS_FETCH)
    .filter(({ payload }) => {
      return payload.type !== 'list' && payload.type !== 'list#shared'
    })
    .mergeMap(action => {
      const { type } = action.payload
      const startTime = Date.now()
      return fetchAssets$({ type, client })
        .delayWhen(() => Observable.timer(500 + startTime - Date.now()))
        .exhaustMap(data => {
          return Observable.of({
            type: actions.ASSETS_FETCH_SUCCESS,
            payload: mapDataToAssets({ type, data })
          })
        })
        .catch(handleError)
    })

export const fetchAssetsFromListEpic = (action$, store, { client }) =>
  action$
    .ofType(actions.ASSETS_FETCH)
    .filter(({ payload }) => {
      return payload.type === 'list'
    })
    .mergeMap(({ payload }) => {
      return Observable.from(
        client.query({
          query: WatchlistGQL,
          context: { isRetriable: true }
        })
      ).concatMap(({ data = {} }) => {
        const startTime = Date.now()
        const { fetchUserLists } = data
        const { listItems = [] } =
          fetchUserLists.find(item => item.id === payload.list.id) || {}
        const queries = listItems
          .map(asset => {
            return asset.project.slug
          })
          .map(slug => {
            return client.query({
              query: projectBySlugGQL,
              variables: { slug },
              context: { isRetriable: true }
            })
          })

        if (listItems.length === 0) {
          return Observable.of({
            type: actions.ASSETS_FETCH_SUCCESS,
            payload: {
              items: [],
              isLoading: false,
              error: false
            }
          })
        }

        return Observable.forkJoin(queries)
          .delayWhen(() => Observable.timer(500 + startTime - Date.now()))
          .mergeMap(data => {
            const items =
              data.map(project => {
                return project.data.projectBySlug
              }) || []
            return Observable.of({
              type: actions.ASSETS_FETCH_SUCCESS,
              payload: {
                items,
                isLoading: false,
                error: false
              }
            })
          })
          .catch(handleError)
      })
    })

export const fetchAssetsFromSharedListEpic = (action$, store, { client }) =>
  action$
    .ofType(actions.ASSETS_FETCH)
    .filter(({ payload }) => {
      return payload.type === 'list#shared'
    })
    .mergeMap(({ payload }) => {
      return Observable.from(
        client.query({
          query: publicWatchlistGQL
        })
      ).concatMap(({ data = {} }) => {
        const startTime = Date.now()
        const { fetchAllPublicUserLists } = data
        const { listItems = [] } =
          fetchAllPublicUserLists.find(item => item.id === payload.list.id) ||
          {}
        const queries = listItems
          .map(asset => {
            return asset.project.slug
          })
          .map(slug => {
            return client.query({
              query: projectBySlugGQL,
              variables: { slug },
              context: { isRetriable: true }
            })
          })

        if (listItems.length === 0) {
          return Observable.of({
            type: actions.ASSETS_FETCH_SUCCESS,
            payload: {
              items: [],
              isLoading: false,
              error: false
            }
          })
        }

        return Observable.forkJoin(queries)
          .delayWhen(() => Observable.timer(500 + startTime - Date.now()))
          .mergeMap(data => {
            const items =
              data.map(project => {
                return project.data.projectBySlug
              }) || []
            return Observable.of({
              type: actions.ASSETS_FETCH_SUCCESS,
              payload: {
                items,
                isLoading: false,
                error: false
              }
            })
          })
          .catch(handleError)
      })
    })
