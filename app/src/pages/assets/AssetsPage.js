import React from 'react'
import { Helmet } from 'react-helmet'
import { getOrigin } from '../../utils/utils'
import Assets from './Assets'
import AssetsTable from './AssetsTable'
import HelpPopupAssets from './HelpPopupAssets'
import AssetsPageNavigation from './AssetsPageNavigation'
import WatchlistShare from '../../components/WatchlistShare/WatchlistShare'
import WidgetList from '../../components/Widget/WidgetList'
import qs from 'query-string'
import './Assets.css'

const getHeadTitle = (type, searchParams) => {
  switch (type) {
    case 'all':
      return 'All Assets'
    case 'currencies':
      return 'Currencies'
    case 'erc20':
      return 'ERC20 Assets'
    case 'list':
      return (qs.parse(searchParams).name || '').split('@')[0].toUpperCase()
    default:
      return 'Assets'
  }
}

const AssetsPage = props => (
  <div className='page projects-table'>
    <Helmet>
      <title>Assets</title>
      <link rel='canonical' href={`${getOrigin()}/assets`} />
    </Helmet>
    {props.isBetaModeEnabled && (
      <WidgetList type={props.type} isLoggedIn={props.isLoggedIn} />
    )}
    <div className='page-head page-head-projects'>
      <div className='page-head-projects__left'>
        <h1>{getHeadTitle(props.type, props.location.search)}</h1>
        <HelpPopupAssets />
        {props.type === 'list' &&
          props.location.hash !== '#shared' && <WatchlistShare />}
      </div>
      <AssetsPageNavigation
        isLoggedIn={props.isLoggedIn}
        location={props.location}
      />
    </div>
    <Assets
      {...props}
      type={props.type}
      render={Assets => (
        <AssetsTable
          Assets={Assets}
          goto={props.history.push}
          preload={props.preload}
        />
      )}
    />
  </div>
)

export default AssetsPage
