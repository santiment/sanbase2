import React from 'react'
import {
  createSkeletonProvider,
  createSkeletonElement
} from '@trainline/react-skeletor'
import { compose } from 'recompose'
import ProjectIcon from './../../components/ProjectIcon'
import PercentChanges from './../../components/PercentChanges'
import ListsPopup from './../../components/ListsPopup/ListsPopup'
import { formatCryptoCurrency, formatBTC, formatNumber } from './../../utils/formatting'
import { followedProjectsGQL } from './DetailedGQL'
import './DetailedHeader.css'

const H1 = createSkeletonElement('h1', 'pending-header pending-h1')
const DIV = createSkeletonElement('div', 'pending-header pending-div')

const DetailedHeader = ({
  project = {
    ticker: '',
    name: '',
    description: '',
    slug: ''
  },
  loading,
  empty,
  isLoggedIn
}) => {
  return (
    <div className='detailed-head'>
      <div className='detailed-project-about'>
        <div className='detailed-name'>
          <H1>{project.name}</H1>
          <ProjectIcon name={project.name || ''} size={22} />
          <DIV className='detailed-ticker-name'>
            {(project.ticker || '').toUpperCase()}
          </DIV>
          &nbsp; &nbsp;
          {isLoggedIn &&
            <div className='detailed-favorite'>
              <Popup
                trigger={
                  <i className={`fa fa-2x fa-star${isFollowed ? '' : '-o'}`}
                    onClick={() => handleFollow({
                      projectId: project.id,
                      actionType: isFollowed ? 'unfollowProject' : 'followProject'
                    })}
                    aria-hidden='true' />
                }
                content={isFollowed ? 'Unfollow this project' : 'Follow this project'}
                position='bottom center'
              />
              &nbsp;
              <ListsPopup />
            </div>
          }
        </div>
        <DIV className='datailed-project-description'>
          {project.description}
        </DIV>
      </div>

      <div className='detailed-price'>
        <div className='detailed-price-description'>Today's changes</div>
        <div className='detailed-price-usd'>
          {formatNumber(project.priceUsd, { currency: 'USD' })}&nbsp;
          {!loading &&
            project && <PercentChanges changes={project.percentChange24h} />}
        </div>
        <div className='detailed-price-btc'>
          {formatCryptoCurrency('BTC', formatBTC(project.priceBtc))}
        </div>
      </div>
    </div>
  )
}

export default compose(
  createSkeletonProvider(
    {
      project: {
        name: '******',
        description: '______ ___ ______ __ _____ __ ______',
        ticker: '',
        percentChange24h: 0,
        priceBtc: 0,
        priceUsd: 0
      }
    },
    ({ loading }) => loading,
    () => ({
      backgroundColor: '#bdc3c7',
      color: '#bdc3c7'
    })
  )
)(DetailedHeader)
