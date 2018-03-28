import React from 'react'
import ReactTable from 'react-table'
import classnames from 'classnames'
import { graphql } from 'react-apollo'
import { withRouter } from 'react-router-dom'
import { Helmet } from 'react-helmet'
import { Message, Loader } from 'semantic-ui-react'
import { compose, pure } from 'recompose'
import 'react-table/react-table.css'
import { FadeIn } from 'animate-components'
import { getOrigin } from '../utils/utils'
import ProjectIcon from './../components/ProjectIcon'
import { simpleSort } from './../utils/sortMethods'
import Panel from './../components/Panel'
import { currenciesGQL } from './Projects/allProjectsGQL'
import {
  refetchThrottled,
  getFilter,
  CustomThComponent,
  CustomHeadComponent,
  Tips,
  PriceColumn,
  VolumeColumn,
  MarketCapColumn
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
          <Message.Header>We're sorry, something has gone wrong on our server.</Message.Header>
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
    maxWidth: 110,
    accessor: d => ({
      name: d.name,
      ticker: d.ticker
    }),
    Cell: ({value}) => (
      <div className='overview-ticker' >
        <ProjectIcon name={value.name} /><br /><span className='ticker'>{value.ticker}</span>
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
  }, PriceColumn, VolumeColumn, MarketCapColumn, {
    Header: 'Dev activity (30D)',
    id: 'github_activity',
    maxWidth: 220,
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
    </div>
  )
}

const mapDataToProps = ({allCurrencies, ownProps}) => {
  const loading = allCurrencies.loading
  const isError = !!allCurrencies.error
  const errorMessage = allCurrencies.error ? allCurrencies.error.message : ''
  const projects = allCurrencies.allCurrencyProjects

  const isEmpty = projects && projects.length === 0
  return {
    Projects: {
      loading,
      isEmpty,
      isError,
      projects,
      errorMessage,
      refetch: allCurrencies.refetch
    }
  }
}

const enhance = compose(
  withRouter,
  graphql(currenciesGQL, {
    name: 'allCurrencies',
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
