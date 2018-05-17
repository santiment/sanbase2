import React from 'react'
import { createSkeletonProvider, createSkeletonElement } from '@trainline/react-skeletor'
import { Popup } from 'semantic-ui-react'
import ProjectIcon from './../../components/ProjectIcon'
import PercentChanges from './../../components/PercentChanges'
import { formatCryptoCurrency, formatBTC, formatNumber } from './../../utils/formatting'
import './DetailedHeader.css'

const H1 = createSkeletonElement('h1', 'pending-header pending-h1')
const DIV = createSkeletonElement('div', 'pending-header pending-div')

const DetailedHeader = ({
  project = {
    ticker: '',
    name: '',
    description: ''
  },
  loading,
  empty,
  dispatch,
  isFavorite,
  isLoggedIn,
  addToFavorites,
  removeFromFavorites
}) => {
  const followProjectHelper = (action) => ({
    variables: {projectId: Number(project.id)},
    update: (proxy, { data }) => {
      dispatch({
        type: 'SET_FOLLOWED_PROJECTS',
        followedProjects: data[`${action === 'remove' ? 'un' : ''}followProject`].followedProjects
      })
    }
  })

  return (
    <div className='detailed-head'>
      <div className='detailed-project-about'>
        <div className='detailed-name'>
          <H1>{project.name}</H1>
          <ProjectIcon
            name={project.name || ''}
            size={22}
          />
          <DIV className='detailed-ticker-name'>
            {(project.ticker || '').toUpperCase()}
          </DIV>
          {isLoggedIn &&
            <div className='detailed-favorite'>
              <Popup
                trigger={
                  <i className={`fa fa-2x fa-star${isFavorite ? '' : '-o'}`}
                    onClick={() => isFavorite ? removeFromFavorites(followProjectHelper('remove')) : addToFavorites(followProjectHelper('add'))}
                    aria-hidden='true' />
                }
                content='Add to favorites'
                position='bottom center'
              />
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
          {!loading && project &&
            <PercentChanges changes={project.percentChange24h} />}
        </div>
        <div className='detailed-price-btc'>
          {formatCryptoCurrency('BTC', formatBTC(project.priceBtc))}
        </div>
      </div>
    </div>
  )
}

export default createSkeletonProvider(
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
)(DetailedHeader)
