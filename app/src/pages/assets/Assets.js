import React from 'react'
import * as qs from 'query-string'
import { Observable } from 'rxjs'
import { tap, zip, mergeMap, concat } from 'rxjs/operators'
import { withApollo } from 'react-apollo'
import { compose, pure } from 'recompose'
import {
  allProjectsGQL,
  allErc20ProjectsGQL,
  currenciesGQL
} from './../Projects/allProjectsGQL'

const MAX_RETRIES = 10

const getTimeout = ({ minTimeout, maxTimeout, attempt }) =>
  Math.min(Math.random() * minTimeout * Math.pow(2, attempt), maxTimeout)

const mapDataToProps = (type, result) => {
  const { loading, error } = result
  const items = !result.error
    ? result.data[pickProjectsType(type).projects]
    : []
  const isEmpty = items && items.length === 0
  return {
    loading,
    isEmpty,
    items,
    error
  }
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

const enhance = compose(withApollo, pure)

class Assets extends React.Component {
  state = {
    Assets: {
      loading: true,
      isEmpty: true,
      isError: false,
      assets: [],
      errorMessage: null,
      refetch: null
    }
  }

  getType = () => {
    const { type = qs.parse(this.props.location.search) } = this.props
    return type
  }

  componentDidMount () {
    const type = this.getType()

    const fetchAssets$ = type =>
      Observable.of(type).switchMap(type =>
        Observable.from(
          this.props.client.query({ query: pickProjectsType(type).gql })
        )
      )

    this.subscription = fetchAssets$(type)
      .retryWhen(errors => {
        return errors.pipe(
          zip(Observable.range(1, MAX_RETRIES), (_, i) => i),
          tap(time => console.log(`Retry to fetch ${time}`)),
          mergeMap(retryCount =>
            Observable.timer(
              getTimeout({
                minTimeout: 1000,
                maxTimeout: 10000,
                attempt: retryCount
              })
            )
          ),
          concat(Observable.throw(new Error('Retry limit exceeded!')))
        )
      })
      .catch(error => {
        return Observable.of({
          error,
          loading: false,
          assets: []
        })
      })
      .subscribe(result => {
        this.setState({ Assets: mapDataToProps(type, result) })
      })
  }

  componentWillUnmount () {
    this.subscription && this.subscription.unsubscribe()
  }

  render () {
    const { children, render } = this.props
    const type = this.getType()
    const { Assets = {} } = this.state
    const props = { type, ...Assets }

    if (typeof children === 'function') return children(props)

    return render(props)
  }
}

export default enhance(Assets)
