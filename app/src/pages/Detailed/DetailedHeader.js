import React from 'react'
import {
  createSkeletonProvider,
  createSkeletonElement
} from '@trainline/react-skeletor'
import { compose } from 'recompose'
import ProjectIcon from './../../components/ProjectIcon'
import PercentChanges from './../../components/PercentChanges'
import WatchlistsPopup from './../../components/WatchlistPopup/WatchlistsPopup'
import ChooseWatchlists from './../../components/WatchlistPopup/ChooseWatchlists'
import { formatNumber } from './../../utils/formatting'
import styles from './DetailedHeader.module.css'

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
  isLoggedIn,
  isDesktop
}) => (
  <div className={styles.wrapper}>
    <div className={styles.left}>
      <DIV className={styles.logo}>
        <ProjectIcon
          name={project.name || ''}
          ticker={project.ticker}
          size={22}
        />
        <div className='detailed-ticker-name'>
          {(project.ticker || '').toUpperCase()}
        </div>
      </DIV>
      <div className={styles.name}>
        <h1>{project.name}</h1>
        <DIV className={styles.description}>{project.description}</DIV>
      </div>
      {isLoggedIn &&
        isDesktop &&
        !loading && (
        <WatchlistsPopup
          projectId={project.id}
          slug={project.slug}
          isLoggedIn={isLoggedIn}
        >
          <ChooseWatchlists />
        </WatchlistsPopup>
      )}
    </div>
    <div className={styles.price}>
      <div className={styles.priceUsd}>
        {project.priceUsd &&
          formatNumber(project.priceUsd, { currency: 'USD' })}
      </div>
      {!loading &&
        project && (
        <PercentChanges
          className={styles.percentChanges}
          changes={project.percentChange24h}
        />
      )}
    </div>
  </div>
)

export default compose(
  createSkeletonProvider(
    {
      project: {
        name: '',
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
