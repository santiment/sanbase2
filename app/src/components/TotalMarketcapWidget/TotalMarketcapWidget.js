import React, { Component } from 'react'
import cx from 'classnames'
import { ResponsiveContainer, AreaChart, Area, XAxis } from 'recharts'
import Widget from '../Widget/Widget'
import {
  getTop3Area,
  combineDataset,
  generateWidgetData
} from './totalMarketcapWidgetUtils'
import './TotalMarketcapWidget.scss'

const WidgetMarketView = {
  LIST: 'List',
  TOTAL: 'Total'
}

const MarketView = ({ currentView, handleViewSelect }) => (
  <>
    View:{' '}
    {Object.values(WidgetMarketView).map(view => (
      <button
        key={view}
        className={cx({
          'TotalMarketcapWidget__view-btn': true,
          active: currentView === view
        })}
        onClick={() => handleViewSelect(view)}
      >
        {view}
      </button>
    ))}
  </>
)

class TotalMarketcapWidget extends Component {
  state = {
    view: WidgetMarketView.LIST
  }

  handleViewSelect = view => {
    this.setState({
      view
    })
  }

  render () {
    const {
      historyPrices: { TOTAL_MARKET, TOTAL_LIST_MARKET, ...restProjects },
      loading,
      listName
    } = this.props

    const { view } = this.state
    const isListView = view === WidgetMarketView.LIST

    let {
      totalmarketCapPrice = '.',
      volumeAmplitudePrice = '.',
      marketcapDataset = []
    } = generateWidgetData(
      TOTAL_LIST_MARKET && isListView ? TOTAL_LIST_MARKET : TOTAL_MARKET
    )

    let restAreas = null

    if (!loading && Object.keys(restProjects).length > 0) {
      const target = isListView
        ? restProjects
        : { [listName]: TOTAL_LIST_MARKET }
      marketcapDataset = combineDataset(marketcapDataset, target)
      restAreas = getTop3Area(target)
    }

    const valueClassNames = `TotalMarketcapWidget__value ${
      totalmarketCapPrice === '.' ? 'TotalMarketcapWidget__value_loading' : ''
    }`

    return (
      <Widget
        className='TotalMarketcapWidget'
        title={
          TOTAL_LIST_MARKET ? (
            <MarketView
              currentView={view}
              handleViewSelect={this.handleViewSelect}
            />
          ) : null
        }
      >
        <div className='TotalMarketcapWidget__info'>
          <div className='TotalMarketcapWidget__left'>
            <h3 className='TotalMarketcapWidget__label'>{`${
              TOTAL_LIST_MARKET && isListView ? 'List' : 'Total'
            } marketcap`}</h3>
            <h4 className={valueClassNames}>{totalmarketCapPrice}</h4>
          </div>
          <div className='TotalMarketcapWidget__right'>
            <h3 className='TotalMarketcapWidget__label'>Vol 24 hr</h3>
            <h4 className={valueClassNames}>{volumeAmplitudePrice}</h4>
          </div>
        </div>
        <ResponsiveContainer
          width='100%'
          className={cx({
            TotalMarketcapWidget__chart: true,
            list: !!TOTAL_LIST_MARKET
          })}
        >
          <AreaChart
            data={marketcapDataset}
            margin={{ top: 0, right: 0, left: 0, bottom: 0 }}
          >
            <XAxis dataKey='datetime' hide />
            <Area
              dataKey='marketcap'
              type='monotone'
              strokeWidth={1}
              stroke='#2d5e39'
              fill='rgba(214, 235, 219, .8)'
              isAnimationActive={false}
            />
            {restAreas}
          </AreaChart>
        </ResponsiveContainer>
      </Widget>
    )
  }
}

export default TotalMarketcapWidget
