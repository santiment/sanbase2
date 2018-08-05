import React from 'react'
import * as qs from 'query-string'
import { connect } from 'react-redux'
import { Observable } from 'rxjs'
import { tap, zip, mergeMap, concat } from 'rxjs/operators'
import { withApollo } from 'react-apollo'
import { compose, pure } from 'recompose'
import * as actions from './../../actions/types.js'
import {
  allProjectsGQL,
  allErc20ProjectsGQL,
  currenciesGQL
} from './../Projects/allProjectsGQL'
import { AssetsListGQL } from './../../components/AssetsListPopup/AssetsListGQL'
import { projectBySlugGQL } from './../../pages/Projects/allProjectsGQL'

const MAX_RETRIES = 10

const getTimeout = ({ minTimeout, maxTimeout, attempt }) =>
  Math.min(Math.random() * minTimeout * Math.pow(2, attempt), maxTimeout)

const getNameIdFromListname = (listname = '') => {
  const data = listname.split('@')
  return {
    listName: data[0],
    listId: data[1]
  }
}

class Assets extends React.Component {
  getType = () => {
    const { listName, listId } = compose(
      getNameIdFromListname,
      parsed => parsed.name,
      qs.parse
    )(this.props.location.search)
    const { type = qs.parse(this.props.location.search) } = this.props
    return { type, listName, listId }
  }

  componentDidMount () {
    console.log('did mount')
    const { type, listName, listId } = this.getType()
    this.props.fetchAssets({
      type,
      list: {
        name: listName,
        id: listId
      }
    })

    // this.subscription = fetchAssets$(type)
    // .retryWhen(errors => {
    // return errors.pipe(
    // zip(Observable.range(1, MAX_RETRIES), (_, i) => i),
    // tap(time => console.log(`Retry to fetch ${time}`)),
    // mergeMap(retryCount =>
    // Observable.timer(
    // getTimeout({
    // minTimeout: 1000,
    // maxTimeout: 10000,
    // attempt: retryCount
    // })
    // )
    // ),
    // concat(Observable.throw(new Error('Retry limit exceeded!')))
    // )
    // })
    // .catch(error => {
    // console.log('error')
    // return Observable.of({
    // error,
    // loading: false,
    // assets: []
    // })
    // })
    // .subscribe(result => {
    // console.log(result)
    // this.setState({ Assets: mapDataToProps(type, result) })
    // })
  }

  componentDidUpdate (prevProps, prevState) {
    if (
      this.props.location.pathname !== prevProps.location.pathname ||
      this.props.location.search !== prevProps.location.search
    ) {
      console.log('fetch')
      const { type, listName, listId } = this.getType()
      this.props.fetchAssets({
        type,
        list: {
          name: listName,
          id: listId
        }
      })
    }
  }

  componentWillUnmount () {
    this.subscription && this.subscription.unsubscribe()
  }

  render () {
    const { children, render } = this.props
    const type = this.getType()
    const { Assets = {} } = this.props
    const props = { type, ...Assets }

    if (typeof children === 'function') return children(props)

    return render(props)
  }
}

const mapStateToProps = state => {
  return {
    Assets: state.projects
  }
}

const mapDispatchToProps = dispatch => ({
  fetchAssets: ({ type, list }) => {
    return dispatch({
      type: actions.ASSETS_FETCH,
      payload: { type, list }
    })
  }
})

const enhance = compose(
  withApollo,
  connect(mapStateToProps, mapDispatchToProps),
  pure
)

export default enhance(Assets)
