import React from 'react'
import ReactTable from 'react-table'
import classnames from 'classnames'
import { graphql } from 'react-apollo'
import { withRouter } from 'react-router-dom'
import { Helmet } from 'react-helmet'
import { Icon, Message, Loader } from 'semantic-ui-react'
import { compose, pure } from 'recompose'
import 'react-table/react-table.css'
import { FadeIn } from 'animate-components'
import { formatNumber } from '../utils/formatting'
import { millify, getOrigin } from '../utils/utils'
import ProjectIcon from './../components/ProjectIcon'
import { simpleSort } from './../utils/sortMethods'
import { getCurrencies } from './Projects/projectSelectors'
import Panel from './../components/Panel'
import allProjectsGQL from './Projects/allProjectsGQL'
import PercentChanges from './../components/PercentChanges'
import {
  refetchThrottled,
  formatMarketCapProject,
  getFilter,
  CustomThComponent,
  CustomHeadComponent,
  Tips
} from './Cashflow.js'
import './Cashflow.css'

export const Currencies = ({
  Projects = {
    projects: [],
    filteredProjects: [],
    loading: true,
    isError: false,
    isEmpty: true,
    refetch: null
  },
  history,
  search,
  tableInfo,
  preload
}) => {
  const { projects, loading } = Projects
  if (Projects.isError) {
    refetchThrottled(Projects)
    return (
      <div style={{display: 'flex', alignItems: 'center', justifyContent: 'center', height: '80vh'}}>
        <Message warning>
          <Message.Header>Something going wrong on our server.</Message.Header>
          <p>Please try again later.</p>
        </Message>
      </div>
    )
  }
  const columns = [{
    Header: '',
    id: 'icon',
    filterable: true,
    sortable: true,
    minWidth: 44,
    accessor: d => ({
      name: d.name,
      ticker: d.ticker
    }),
    Cell: ({value}) => (
      <div className='overview-ticker' >
        <ProjectIcon name={value.name} /><br />{value.ticker}
      </div>
    ),
    filterMethod: (filter, row) => {
      const name = row[filter.id].name || ''
      const ticker = row[filter.id].ticker || ''
      return name.toLowerCase().indexOf(filter.value) !== -1 ||
        ticker.toLowerCase().indexOf(filter.value) !== -1
    }
  }, {
    Header: 'Project',
    id: 'project',
    filterable: true,
    sortable: true,
    accessor: d => ({
      name: d.name,
      ticker: d.ticker,
      cmcId: d.coinmarketcapId
    }),
    Cell: ({value}) => (
      <div
        onMouseOver={() => preload()}
        onClick={() => history.push(`/projects/${value.cmcId}`)}
        className='overview-name' >
        {value.name}
      </div>
    ),
    filterMethod: (filter, row) => {
      const name = row[filter.id].name || ''
      const ticker = row[filter.id].ticker || ''
      return name.toLowerCase().indexOf(filter.value) !== -1 ||
        ticker.toLowerCase().indexOf(filter.value) !== -1
    }
  }, {
    Header: 'Price',
    id: 'price',
    maxWidth: 100,
    accessor: d => ({
      priceUsd: d.priceUsd,
      change24h: d.percentChange24h
    }),
    Cell: ({value: {priceUsd, change24h}}) => <div className='overview-price'>
      {priceUsd ? formatNumber(priceUsd, 'USD') : '---'}
      &nbsp;
      {<PercentChanges changes={change24h} />}
    </div>,
    sortable: true,
    sortMethod: (a, b) => simpleSort(parseFloat(a.priceUsd || 0), parseFloat(b.priceUsd || 0))
  }, {
    Header: 'Volume',
    id: 'volume',
    maxWidth: 100,
    accessor: d => ({
      volumeUsd: d.volumeUsd,
      change24h: d.volumeChange24h
    }),
    Cell: ({value: {volumeUsd, change24h}}) => <div className='overview-volume'>
      {volumeUsd
        ? `$${millify(parseFloat(volumeUsd))}`
        : ''}
      &nbsp;
      {change24h
        ? <PercentChanges changes={change24h} />
        : ''}
    </div>,
    sortable: true,
    sortMethod: (a, b) =>
      simpleSort(
        parseFloat(a.volumeUsd || 0),
        parseFloat(b.volumeUsd || 0)
      )
  }, {
    Header: 'Market Cap',
    id: 'marketcapUsd',
    maxWidth: 130,
    accessor: 'marketcapUsd',
    Cell: ({value}) => <div className='overview-marketcap'>{formatMarketCapProject(value)}</div>,
    sortable: true,
    sortMethod: (a, b) => simpleSort(parseInt(a, 10), parseInt(b, 10))
  }, {
    Header: 'Dev activity (30D)',
    id: 'github_activity',
    maxWidth: 110,
    accessor: d => d.averageDevActivity,
    Cell: ({value}) => <div className='overview-devactivity'>{value ? parseFloat(value).toFixed(2) : ''}</div>,
    sortable: true,
    sortMethod: (a, b) => simpleSort(a, b)
  }]

  return (
    <div className='page cashflow'>
      <Helmet>
        <title>SANbase: Currencies</title>
        <link rel='canonical' href={`${getOrigin()}/projects`} />
      </Helmet>
      <FadeIn duration='0.3s' timingFunction='ease-in' as='div'>
        <div className='cashflow-head'>
          <h1>Currencies</h1>
          <p>
            brought to you by <a
              href='https://santiment.net'
              rel='noopener noreferrer'
              target='_blank'>Santiment</a>
            <br />
            <Icon color='red' name='question circle outline' />Automated data not available.&nbsp;
            <span className='cashflow-head-community-help'>
            Community help locating correct wallet is welcome!</span>
          </p>
        </div>
        <Panel>
          <div className='row'>
            <div className='datatables-info'>
              {false && <label>
                Showing {
                  (tableInfo.visibleItems !== 0)
                    ? (tableInfo.page - 1) * tableInfo.pageSize + 1
                    : 0
                } to {
                  tableInfo.page * tableInfo.pageSize
                } of {tableInfo.visibleItems}
                &nbsp;entries&nbsp;
                {tableInfo.visibleItems !== projects.length &&
                  `(filtered from ${projects.length} total entries)`}
              </label>}
            </div>
          </div>
          <ReactTable
            loading={loading}
            showPagination={false}
            showPaginationTop={false}
            showPaginationBottom={false}
            pageSize={projects && projects.length}
            sortable={false}
            resizable
            defaultSorted={[
              {
                id: 'marketcapUsd',
                desc: false
              }
            ]}
            className='-highlight'
            data={projects}
            columns={columns}
            filtered={getFilter(search)}
            LoadingComponent={({ className, loading, loadingText, ...rest }) => (
              <div
                className={classnames('-loading', { '-active': loading }, className)}
                {...rest}
              >
                <div className='-loading-inner'>
                  <Loader active size='large' />
                </div>
              </div>
            )}
            ThComponent={CustomThComponent}
            TheadComponent={CustomHeadComponent}
            getTdProps={(state, rowInfo, column, instance) => {
              return {
                onClick: (e, handleOriginal) => {
                  if (handleOriginal) {
                    handleOriginal()
                  }
                  if (rowInfo && rowInfo.original && rowInfo.original.ticker) {
                    history.push(`/projects/${rowInfo.original.coinmarketcapId}`)
                  }
                }
              }
            }}
          />
        </Panel>
      </FadeIn>
      <Tips />
      <div className='cashflow-indev-message'>
        NOTE: This app is in development.
        We give no guarantee data is correct as we are in active development.
      </div>
    </div>
  )
}

const mapDataToProps = ({allProjects, ownProps}) => {
  const loading = allProjects.loading
  const isError = !!allProjects.error
  const errorMessage = allProjects.error ? allProjects.error.message : ''
  const projects = getCurrencies(allProjects.allProjects)

  const isEmpty = projects.length === 0
  return {
    Projects: {
      loading,
      isEmpty,
      isError,
      projects,
      errorMessage,
      refetch: allProjects.refetch
    }
  }
}

const enhance = compose(
  withRouter,
  graphql(allProjectsGQL, {
    name: 'allProjects',
    props: mapDataToProps,
    options: () => {
      return {
        errorPolicy: 'all',
        notifyOnNetworkStatusChange: true
      }
    }
  }),
  pure
)

export default enhance(Currencies)
