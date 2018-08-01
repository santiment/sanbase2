import React from 'react'
import { Helmet } from 'react-helmet'
import { getOrigin } from '../../utils/utils'
import { FadeIn } from 'animate-components'
import Assets from './Assets'
import AssetsTable from './AssetsTable'
import HelpPopupAssets from './HelpPopupAssets'

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
    </div>
    <Assets
      {...props}
      type={props.type}
      render={({ items, ...rest }) => (
        <FadeIn duration='0.3s' timingFunction='ease-in' as='div'>
          <AssetsTable
            Assets={{
              items,
              ...rest
            }}
            goto={props.history.push}
            preload={props.preload}
          />
        </FadeIn>
      )}
    />
  </div>
)

export default AssetsPage
