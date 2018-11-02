import React from 'react'
import { Helmet } from 'react-helmet'
import { getOrigin } from '../../utils/utils'
import Assets from './Assets'
import AssetsTable from './AssetsTable'
import HelpPopupAssets from './HelpPopupAssets'
import AssetsPageNavigation from './AssetsPageNavigation'
import WatchlistShare from '../../components/WatchlistShare/WatchlistShare'
import './Assets.css'
import PiechartWatchlistWidget from '../../components/PiechartWatchlistWidget/PiechartWatchlistWidget'

const AssetsPage = props => (
  <div className='page projects-table'>
    <PiechartWatchlistWidget locationType={props.type} />
    <Helmet>
      <title>Assets</title>
      <link rel='canonical' href={`${getOrigin()}/assets`} />
    </Helmet>
    <div className='page-head page-head-projects'>
      <div className='page-head-projects__left'>
        <h1>Assets</h1>
        <HelpPopupAssets />
        {props.type === 'list' &&
          props.location.hash !== '#shared' && <WatchlistShare />}
      </div>
      <AssetsPageNavigation isLoggedIn={props.isLoggedIn} />
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
