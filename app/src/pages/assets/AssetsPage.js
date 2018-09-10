import React from 'react'
import { Helmet } from 'react-helmet'
import { getOrigin } from '../../utils/utils'
import Assets from './Assets'
import AssetsTable from './AssetsTable'
import HelpPopupAssets from './HelpPopupAssets'
import AssetsPageNavigation from './AssetsPageNavigation'
import './Assets.css'

const AssetsPage = props => (
  <div className='page projects-table'>
    <Helmet>
      <title>Assets</title>
      <link rel='canonical' href={`${getOrigin()}/assets`} />
    </Helmet>
    <div className='page-head page-head-projects'>
      <div className='page-head-projects__left'>
        <h1>Assets</h1>
        <HelpPopupAssets />
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
