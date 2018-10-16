import React from 'react'
import { connect } from 'react-redux'
import { compose } from 'recompose'

class AssetsChartContainer extends React.Component {
  render () {
    const { render, timeRange } = this.props
    return render({
      isLoading: true,
      timeRange
    })
  }
}

const mapStateToProps = ({ assetsChart }) => ({
  timeRange: assetsChart.timeRange,
  currency: assetsChart.currency
})

const enhance = compose(
  connect(
    mapStateToProps,
    null
  )
)

export default enhance(AssetsChartContainer)
