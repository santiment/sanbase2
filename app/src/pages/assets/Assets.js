import React from 'react'
import * as qs from 'query-string'
import { connect } from 'react-redux'
import { compose, pure } from 'recompose'
import * as actions from './../../actions/types.js'

class Assets extends React.Component {
  getNameIdFromListname = (listname = '') => {
    const data = listname.split('@')
    return {
      listName: data[0],
      listId: data[1]
    }
  }

  getType = () => {
    const { listName, listId } = compose(
      this.getNameIdFromListname,
      parsed => parsed.name,
      qs.parse
    )(this.props.location.search)
    const { type = qs.parse(this.props.location.search) } = this.props
    return { type, listName, listId }
  }

  componentDidMount () {
    const { type, listName, listId } = this.getType()
    this.props.fetchAssets({
      type,
      list: {
        name: listName,
        id: listId
      }
    })
  }

  componentDidUpdate (prevProps, prevState) {
    if (
      this.props.location.pathname !== prevProps.location.pathname ||
      this.props.location.search !== prevProps.location.search
    ) {
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

const enhance = compose(connect(mapStateToProps, mapDispatchToProps), pure)

export default enhance(Assets)
