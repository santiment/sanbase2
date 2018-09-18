import React from 'react'
import { connect } from 'react-redux'
import { compose, pure } from 'recompose'
import * as actions from './../actions/types.js'

class GetTimeSeries extends React.Component {
  componentDidMount () {
    this.props.fetchTimeseries({
      price: this.props.price
    })
  }

  // componentDidUpdate (prevProps, prevState) {
  // const { pathname, search } = this.props.location || {}
  // if (
  // pathname !== (prevProps.location || {}).pathname ||
  // search !== (prevProps.location || {}).search
  // ) {
  // const { type, listName, listId } = this.getType()
  // this.props.fetchAssets({
  // type,
  // list: {
  // name: listName,
  // id: listId
  // }
  // })
  // }
  // }

  render () {
    const { render, timeseries = {} } = this.props
    return render({
      timeseries
    })
  }
}

const mapStateToProps = state => {
  return {
    timeseries: state.timeseries
  }
}

const mapDispatchToProps = dispatch => ({
  fetchTimeseries: ({ price }) => {
    return dispatch({
      type: actions.TIMESERIES_FETCH,
      payload: { price }
    })
  }
})

const enhance = compose(connect(mapStateToProps, mapDispatchToProps), pure)

export default enhance(GetTimeSeries)
