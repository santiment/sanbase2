import React from 'react'
import { createSkeletonProvider, createSkeletonElement } from '@trainline/react-skeletor'
import { compose } from 'recompose'
import { graphql } from 'react-apollo'
import { Popup } from 'semantic-ui-react'
import ProjectIcon from './../../components/ProjectIcon'
import PercentChanges from './../../components/PercentChanges'
import { formatCryptoCurrency, formatBTC, formatNumber } from './../../utils/formatting'
import { followedProjectsGQL } from './../Login/LoginGQL'
import { FollowProjectGQL, UnfollowProjectGQL } from './DetailedGQL'
import './DetailedHeader.css'

const H1 = createSkeletonElement('h1', 'pending-header pending-h1')
const DIV = createSkeletonElement('div', 'pending-header pending-div')

const followProjectHelper = (action, project) => ({
  variables: {projectId: Number(project.id)},
  optimisticResponse: {
    __typename: 'Mutation',
    [action]: {
      __typename: 'Project',
      id: project.id
    }
  },
  update: (proxy) => {
    let data = proxy.readQuery({ query: followedProjectsGQL })
    const newFollowedProjects = data.followedProjects ? [...data.followedProjects] : []
    if (action === 'followProject') {
      newFollowedProjects.push({
        id: project.id,
        __typename: 'Project'
      })
      data.followedProjects = newFollowedProjects
    } else if (action === 'unfollowProject') {
      data.followedProjects = newFollowedProjects.filter(current => current.id !== project.id)
    }
    proxy.writeQuery({ query: followedProjectsGQL, data })
  }
})

const DetailedHeader = ({
  project = {
    ticker: '',
    name: '',
    description: ''
  },
  loading,
  empty,
  dispatch,
  isLoggedIn,
  isFavorite,
  followProject,
  unfollowProject
}) => {
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
          {isLoggedIn && !loading &&
            <div className='detailed-favorite'>
              <Popup
                trigger={
                  <i className={`fa fa-2x fa-star${isFavorite ? '' : '-o'}`}
                    onClick={() => {
                      isFavorite
                        ? unfollowProject(followProjectHelper('unfollowProject', project))
                        : followProject(followProjectHelper('followProject', project))
                    }}
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
  ),
  graphql(followedProjectsGQL, {
    name: 'FollowedProjects',
    props: ({FollowedProjects, ownProps}) => {
      const { followedProjects = [] } = FollowedProjects
      const { project = {} } = ownProps
      return {
        isFavorite: followedProjects && followedProjects.some(val => {
          return val.id === project.id
        })
      }
    }
  }),
  graphql(FollowProjectGQL, {
    name: 'followProject'
  }),
  graphql(UnfollowProjectGQL, {
    name: 'unfollowProject'
  })
)(DetailedHeader)
