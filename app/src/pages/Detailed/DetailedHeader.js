import React from 'react'
import { createSkeletonProvider, createSkeletonElement } from '@trainline/react-skeletor'
import ProjectIcon from './../../components/ProjectIcon'
import PercentChanges from './../../components/PercentChanges'
import { formatNumber, formatBTC } from '../../utils/formatting'
import './DetailedHeader.css'

const H1 = createSkeletonElement('h1', 'pending-header pending-h1')
const DIV = createSkeletonElement('div', 'pending-header pending-div')

const DetailedHeader = ({project = {
  ticker: '',
  name: '',
  description: ''
}, loading, empty}) => (
  <div className='detailed-head'>
    <div className='detailed-project-about'>
      <div className='detailed-name'>
        <H1>{project.name}</H1>
        <ProjectIcon
          name={project.name || ''}
          size={24} />
        <DIV className='detailed-ticker-name'>
          {(project.ticker || '').toUpperCase()}
        </DIV>
      </div>
      <DIV className='datailed-project-description'>
        {project.description}
      </DIV>
    </div>

    <div className='detailed-price'>
      <div className='detailed-price-description'>Today's changes</div>
      <div className='detailed-price-usd'>
        {formatNumber(project.priceUsd, 'USD')}&nbsp;
        {!loading && project &&
          <PercentChanges changes={project.percentChange24h} />}
      </div>
      <div className='detailed-price-btc'>
        BTC {formatBTC(parseFloat(project.priceBtc))}
      </div>
    </div>
  </div>
)

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
