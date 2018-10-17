import React from 'react'
import { connect } from 'react-redux'
import { Label } from 'semantic-ui-react'
import ToggleButton from './ToggleButton'
import { ASSETS_CHART_TOGGLE_VOLUME } from './AssetsChart.reducers'

const AssetsChartFooter = ({ isToggledVolume, toggleVolume }) => (
  <div>
    <ToggleButton isToggled={isToggledVolume} toggle={toggleVolume}>
      <Label circular className='volumeLabel' empty />
      Volume
    </ToggleButton>
  </div>
)

const mapStateToProps = ({ assetsChart }) => ({
  isToggledVolume: assetsChart.isToggledVolume
})

const mapDispatchToProps = dispatch => ({
  toggleVolume: () =>
    dispatch({
      type: ASSETS_CHART_TOGGLE_VOLUME
    })
})

export default connect(
  mapStateToProps,
  mapDispatchToProps
)(AssetsChartFooter)
