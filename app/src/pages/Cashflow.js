import React from 'react'
import ReactTable from 'react-table'
import { graphql } from 'react-apollo'
import { connect } from 'react-redux'
import { withRouter } from 'react-router-dom'
import { Icon, Popup } from 'semantic-ui-react'
import { compose, pure } from 'recompose'
import 'react-table/react-table.css'
import { FadeIn } from 'animate-components'
import { formatNumber } from '../utils/formatting'
import { millify } from '../utils/utils'
import ProjectIcon from './../components/ProjectIcon'
import { simpleSort } from './../utils/sortMethods'
import Panel from './../components/Panel'
import allProjectsGQL from './allProjectsGQL'
import PercentChanges from './../components/PercentChanges'
import './Cashflow.css'

const formatBalance = ({ethBalance, usdBalance, project, ticker}) => (
  <div className='wallet'>
    <div className='usd first'>{`$${millify(parseFloat(usdBalance))}`}</div>
    <div className='eth'>
      {parseFloat(ethBalance) === 0 &&
        <Popup
          trigger={<div style={{display: 'inline-block'}}>{
            <a
              target='_blank'
              rel='noopener noreferrer'
              href={`https://santiment.typeform.com/to/bT0Dgu?project=${project}&ticker=${ticker}`}>
              <Icon color='red' name='question circle outline' />
            </a>}
          </div>}
          content='Community help locating correct wallet is welcome!'
          position='top center'
        />
      }
      {ethBalance
        ? `ETH ${millify(parseFloat(parseFloat(ethBalance).toFixed(2)))}`
        : '---'}
    </div>
  </div>
)

const formatMarketCapProject = marketcapUsd => {
  if (marketcapUsd !== null) {
    return `$${millify(parseFloat(marketcapUsd))}`
  } else {
    return 'No data'
  }
}

const getFilter = search => {
  if (search) {
    return [{
      id: 'project',
      value: search
    }]
  }
  return []
}

export const Cashflow = ({
  Projects = {
    projects: [],
    filteredProjects: [],
    loading: true,
    isError: false,
    isEmpty: true
  },
  onSearch,
  history,
  search,
  tableInfo,
  preload
}) => {
  const { projects, loading } = Projects
  const columns = [{
    Header: 'Project',
    id: 'project',
    filterable: true,
    sortable: true,
    minWidth: 190,
    accessor: d => ({
      name: d.name,
      ticker: d.ticker
    }),
    Cell: ({value}) => (
      <div
        onMouseOver={() => preload()}
        onClick={() => history.push(`/projects/${value.ticker.toLowerCase()}`)} >
        <ProjectIcon name={value.name} /> {value.name} ({value.ticker})
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
    accessor: d => ({
      priceUsd: d.priceUsd,
      change24h: d.percentChange24h
    }),
    Cell: ({value}) => <div style={{
      fontSize: '16px',
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center'
    }}>
      {value.priceUsd ? formatNumber(value.priceUsd, 'USD') : '---'}
      &nbsp;
      {<PercentChanges changes={value.change24h} />}
    </div>,
    sortable: true,
    sortMethod: (a, b) => simpleSort(parseFloat(a.priceUsd || 0), parseFloat(b.priceUsd || 0))
  }, {
    Header: 'Volume',
    id: 'volume',
    accessor: d => ({
      volumeUsd: d.volumeUsd,
      change24h: d.volumeChange24h
    }),
    Cell: ({value}) => <div style={{
      fontSize: '16px',
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center'
    }}>
      {value.volumeUsd
        ? `$${millify(parseFloat(value.volumeUsd))}`
        : '---'}
      &nbsp;
      {<PercentChanges changes={value.change24h} />}
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
    accessor: 'marketcapUsd',
    Cell: ({value}) => <div className='market-cap'>{formatMarketCapProject(value)}</div>,
    sortable: true,
    sortMethod: (a, b) => simpleSort(parseInt(a, 10), parseInt(b, 10))
  }, {
    Header: 'Balance (USD/ETH)',
    id: 'balance',
    accessor: d => ({
      project: d.name,
      ticker: d.ticker,
      ethBalance: d.ethBalance,
      usdBalance: d.usdBalance
    }),
    Cell: ({value}) => <div>{formatBalance(value)}</div>,
    sortable: true,
    sortMethod: (a, b) =>
      simpleSort(
        parseFloat(a.ethBalance || 0),
        parseFloat(b.ethBalance || 0)
      )
  }, {
    Header: 'Price/Book Ratio',
    id: 'pbr',
    accessor: 'priceToBookRatio',
    Cell: ({value}) => <div>{value &&
      ((value) => {
        if (value > 1000000000000) {
          return ''
        }
        return value < 1000 ? formatNumber(parseFloat(value).toFixed(3)) : millify(parseFloat(value))
      })(value)
    }</div>,
    sortable: true,
    sortMethod: (a, b) => {
      if (a > 1000000000000) {
        return 1
      }
      return simpleSort(
        parseFloat(a || 0),
        parseFloat(b || 0)
      )
    }
  }, {
    Header: 'ETH spent 30D',
    id: 'tx',
    accessor: d => d.ethSpent,
    Cell: ({value}) => <div>{`ETH ${formatNumber(value)}`}</div>,
    sortable: true,
    sortMethod: (a, b) => simpleSort(a, b)
  }, {
    Header: 'Dev activity 30D',
    id: 'github_activity',
    accessor: d => d.averageDevActivity,
    Cell: ({value}) => <div>{value ? parseFloat(value).toFixed(2) : '---'}</div>,
    sortable: true,
    sortMethod: (a, b) => simpleSort(a, b)
  }, {
    Header: 'Signals',
    id: 'signals',
    maxWidth: 40,
    accessor: d => ({
      warning: d.signals && d.signals.length > 0,
      description: d.signals[0] && d.signals[0].description
    }),
    Cell: ({value}) => <div >
      {value.warning &&
        <Popup basic
          position='right center'
          hideOnScroll
          wide
          inverted
          trigger={<Icon color='orange' fitted name='warning sign' />}
          on='hover'>
          {value.description}
        </Popup>}
    </div>,
    sortable: true,
    sortMethod: (a, b) => simpleSort(a.warning, b.warning)
  }]

  return (
    <div className='page cashflow'>
      <FadeIn duration='0.7s' timingFunction='ease-in' as='div'>
        <div className='cashflow-head'>
          <h1>Projects</h1>
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
            <div className='datatables-filter'>
              <label>
                <input placeholder='Search' onKeyUp={onSearch} />
              </label>
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
                id: 'market_cap_usd',
                desc: false
              }
            ]}
            className='-highlight'
            data={projects}
            columns={columns}
            filtered={getFilter(search)}
            getTdProps={(state, rowInfo, column, instance) => {
              return {
                onClick: (e, handleOriginal) => {
                  if (handleOriginal) {
                    handleOriginal()
                  }
                  history.push(`/projects/${rowInfo.original.ticker.toLowerCase()}`)
                }
              }
            }}
          />
        </Panel>
      </FadeIn>
      <div className='cashflow-indev-message'>
        NOTE: This app is in development.
        We give no guarantee data is correct as we are in active development.
      </div>
    </div>
  )
}

const mapStateToProps = state => {
  return {
    search: state.projects.search,
    tableInfo: state.projects.tableInfo
  }
}

const mapDispatchToProps = dispatch => {
  return {
    onSearch: (event) => {
      dispatch({
        type: 'SET_SEARCH',
        payload: {
          search: event.target.value.toLowerCase()
        }
      })
    }
  }
}

const mapDataToProps = ({allProjects, ownProps}) => {
  const loading = allProjects.loading
  const isError = !!allProjects.error
  const errorMessage = allProjects.error ? allProjects.error.message : ''
  const projects = (allProjects.allProjects || [])
    .filter(project => {
      const defaultFilter = project.ethAddresses &&
        project.ethAddresses.length > 0 &&
        project.rank &&
        project.volumeUsd > 0
      return defaultFilter
    })

  const isEmpty = projects.length === 0
  return {
    Projects: {
      loading,
      isEmpty,
      isError,
      projects,
      errorMessage
    }
  }
}

const enhance = compose(
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
  withRouter,
  graphql(allProjectsGQL, {
    name: 'allProjects',
    props: mapDataToProps,
    options: () => {
      return {
        errorPolicy: 'all'
      }
    }
  }),
  pure
)

export default enhance(Cashflow)
