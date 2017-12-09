import React from 'react'
import { connect } from 'react-redux'
import { compose } from 'recompose'
import isEqual from 'lodash.isequal'
import * as actions from './../actions/types.js'

class GetTimeSeries extends React.Component {
  componentDidMount () {
    this.props.fetchTimeseries({
      price: this.props.price
    })
  }

  componentDidUpdate (prevProps, prevState) {
    if (!isEqual(this.props.price, prevProps.price)) {
      this.props.fetchTimeseries({
        price: this.props.price
      })
    }
  }

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

const enhance = compose(
  connect(
    mapStateToProps,
    mapDispatchToProps
  )
)

export default enhance(GetTimeSeries)
