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
    const { search, hash } = this.props.location || {}
    const { listName, listId } = compose(
      this.getNameIdFromListname,
      parsed => parsed.name,
      qs.parse
    )(search)
    const type =
      hash === '#shared' ? 'list#shared' : this.props.type || qs.parse(search)
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
    const { pathname, search } = this.props.location || {}
    if (
      pathname !== (prevProps.location || {}).pathname ||
      search !== (prevProps.location || {}).search
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
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
  pure
)

export default enhance(Assets)
