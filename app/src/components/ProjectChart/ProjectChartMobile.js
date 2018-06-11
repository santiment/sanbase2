import React, { Fragment } from 'react'
import { connect } from 'react-redux'
import { compose } from 'recompose'
import { Button } from 'semantic-ui-react'
import Analytics from './../Analytics'
import { formatNumber, millify } from './../../utils/formatting'
import './ProjectChartMobile.css'

const ProjectChartMobile = ({
  historyTwitterData = {
    items: [],
    loading: true
  },
  price = {
    history: {
      items: [],
      loading: true
    }
  },
  burnRate = {
    items: [],
    loading: true
  },
  github = {
    history: {
      items: [],
      loading: true
    }
  },
  project = {
    fundsRaisedUsdIcoEndPrice: null,
    icoPrice: null
  },
  settings = {
    showed: {
      'priceUsd': true,
      'volume': true,
      'marketcap': true
    }
  },
  routerHistory,
  isToggledFullscreen,
  toggleFullscreen,
  isToggledMinimap,
  toggleMiniMap,
  isERC20
}) => {
  const icoPrice = project.icoPrice
  const icoPriceUSD = icoPrice
    ? formatNumber(icoPrice, { currency: 'USD' })
    : undefined
  return (
    <Fragment>
      <div className='detailed-page-mobile-settings-bar'>
        <Button
          positive={isToggledFullscreen}
          onClick={toggleFullscreen} basic >
          Old view (more data)
        </Button>
        <Button
          positive={isToggledMinimap}
          onClick={toggleMiniMap} basic >
          Minimap
        </Button>
      </div>
      {(settings.showed['priceUsd'] ||
        settings.showed['volume'] ||
        settings.showed['marketcap']) &&
        <h2>FINANCIAL</h2>}
      {icoPrice &&
        <div className='ico-price-label'>
          {`ICO Price ${icoPriceUSD}`}
          <div className='ico-price-legend' />
        </div>}
      {settings.showed['priceUsd'] && <Analytics
        data={price.history}
        label='priceUsd'
        show='Price USD'
        formatData={price => {
          return formatNumber(price, { currency: 'USD' })
        }}
        chart={{
          type: 'line',
          color: 'rgb(52, 171, 107)',
          fill: true,
          borderWidth: 1,
          pointBorderWidth: 2,
          syncId: 'financial',
          referenceLine: {
            y: +icoPrice
          }
        }}
      />}
      {settings.showed['volume'] && <Analytics
        data={price.history}
        label='volume'
        formatData={volumeUsd => {
          return `$${millify(volumeUsd)}`
        }}
        chart={{
          type: 'bar',
          color: 'rgb(38, 43, 51)',
          fill: false,
          borderWidth: 1,
          syncId: 'financial',
          pointBorderWidth: 2,
          withMiniMap: isToggledMinimap
        }}
        show='Volume'
      />}
      {settings.showed['marketcap'] && <Analytics
        data={price.history}
        label='marketcap'
        chart={{
          type: 'line',
          color: 'rgb(52, 118, 153)',
          syncId: 'financial'
        }}
        formatData={marketcapUsd => {
          return `$${millify(marketcapUsd)}`
        }}
        show='Marketcap'
      />}
      {isERC20 && settings.showed['burnRate'] &&
      <Fragment>
        <h2>BLOCKCHAIN</h2>
        {settings.showed['burnRate'] && <Analytics
          data={burnRate}
          label='burnRate'
          formatData={burnRate => {
            return `${millify(burnRate)} (tokens × blocks)`
          }}
          chart={{
            type: 'bar',
            color: 'rgba(252, 138, 23, 0.7)',
            fill: false,
            borderWidth: 1,
            pointBorderWidth: 2
          }}
          show='Burnrate'
          showInfo={false}
        />}
      </Fragment>}
      {settings.showed['followersCount'] && <h2>SOCIAL</h2>}
      {settings.showed['followersCount'] && <Analytics
        data={historyTwitterData}
        label='followersCount'
        show='Twitter followers'
      />}
      {settings.showed['activity'] && <h2>DEVELOPMENT</h2>}
      {settings.showed['activity'] && <Analytics
        data={github.history}
        label='activity'
        chart={{
          type: 'line',
          color: 'rgba(96, 76, 141)'
        }}
        show='Github Activity'
        showInfo
      />}
      {settings.showed['ethSpent'] && <h2>ETHEREUM</h2>}
    </Fragment>
  )
}

const mapStateToProps = state => {
  return {
    isToggledFullscreen: state.detailedPageUi.isToggledFullscreen,
    isToggledMinimap: state.detailedPageUi.isToggledMinimap,
    isToggledBurnRate: state.detailedPageUi.isToggledBurnRate
  }
}

const mapDispatchToProps = dispatch => {
  return {
    toggleFullscreen: () => {
      dispatch({
        type: 'TOGGLE_FULLSCREEN_MOBILE'
      })
    },
    toggleMiniMap: () => {
      dispatch({
        type: 'TOGGLE_MINIMAP'
      })
    },
    toggleBurnRate: () => {
      dispatch({
        type: 'TOGGLE_BURNRATE'
      })
    }
  }
}

export default compose(
  connect(
    mapStateToProps,
    mapDispatchToProps
  )
)(ProjectChartMobile)
