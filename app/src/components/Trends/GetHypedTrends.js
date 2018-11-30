import React from 'react'
import { connect } from 'react-redux'
import { compose, pure } from 'recompose'
import * as actions from './actions.js'

class GetHypedTrends extends React.Component {
  render () {
    const { render, ...rest } = this.props
    return render(rest)
  }

  componentDidMount () {
    this.props.fetchHypedTrends()
  }
}

const mapStateToProps = state => {
  return {
    ...state.hypedTrends
  }
}

const mapDispatchToProps = dispatch => ({
  fetchHypedTrends: () => {
    return dispatch({
      type: actions.TRENDS_HYPED_FETCH
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

export default enhance(GetHypedTrends)
