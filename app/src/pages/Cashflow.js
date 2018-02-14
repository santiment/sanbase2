import React from 'react'
import ReactTable from 'react-table'
import { graphql } from 'react-apollo'
import { connect } from 'react-redux'
import { withRouter } from 'react-router-dom'
import { Icon, Popup } from 'semantic-ui-react'
import { compose, pure } from 'recompose'
import 'react-table/react-table.css'
import { FadeIn } from 'animate-components'
import moment from 'moment'
import { formatNumber } from '../utils/formatting'
import ProjectIcon from './../components/ProjectIcon'
import { simpleSort } from './../utils/sortMethods'
import Panel from './../components/Panel'
import allProjectsGQL from './allProjectsGQL'
import PercentChanges from './../components/PercentChanges'
import './Cashflow.css'

const formatDate = date => moment(date).format('YYYY-MM-DD')

export const formatLastOutgoingWallet = wallets => {
  return wallets.map((wallet, index) => {
    const lastOutgoing = wallet.last_outgoing !== null
      ? formatDate(wallet.last_outgoing) : 'No recent transfers'
    return (
      <div key={index}>
        { lastOutgoing }
      </div>
    )
  })
}

export const formatTxOutWallet = wallets => {
  return wallets.map((wallet, index) => {
    const txOut = wallet.tx_out || '0.00'
    return (
      <div key={index}>
        {formatNumber(txOut)}
      </div>
    )
  })
}

export const formatBalanceWallet = ({wallets, ethPrice}) => {
  return wallets.map((wallet, index) => {
    const balance = wallet.balance || 0
    return (
      <div className='wallet' key={index}>
        <div className='usd first'>{formatNumber((balance * ethPrice), 'USD')}</div>
        <div className='eth'>
          {parseFloat(balance) === 0 &&
            <Popup
              trigger={<div style={{display: 'inline-block'}}>{
                <a
                  target='_blank'
                  rel='noopener noreferrer'
                  href='https://santiment.typeform.com/to/bT0Dgu'>
                  <Icon color='red' name='question circle outline' />
                </a>}
              </div>}
              content='Community help locating correct wallet is welcome!'
              position='top center'
            />
          }
          <a
            className='address'
            href={'https://etherscan.io/address/' + wallet.address}
            target='_blank'>Ξ{formatNumber(balance)}&nbsp;
            <i className='fa fa-external-link' />
          </a>
        </div>
      </div>
    )
  })
}

const formatBalance = ({ethBalance, usdBalance}) => (
  <div className='wallet'>
    <div className='usd first'>{formatNumber((usdBalance), 'USD')}</div>
    <div className='eth'>
      {parseFloat(ethBalance) === 0 &&
        <Popup
          trigger={<div style={{display: 'inline-block'}}>{
            <a
              target='_blank'
              rel='noopener noreferrer'
              href='https://santiment.typeform.com/to/bT0Dgu'>
              <Icon color='red' name='question circle outline' />
            </a>}
          </div>}
          content='Community help locating correct wallet is welcome!'
          position='top center'
        />
      }
      {`ETH ${formatNumber(ethBalance)}`}
    </div>
  </div>
)

const formatMarketCapProject = cap => {
  if (cap !== null) {
    return formatNumber(cap, 'USD')
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
    Header: 'Signals',
    id: 'signals',
    minWidth: 60,
    accessor: d => ({
      warning: d.signals && d.signals.length > 0,
      description: d.signals[0] && d.signals[0].description
    }),
    Cell: ({value}) => <div style={{textAlign: 'center'}}>
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
  }, {
    Header: 'Price',
    id: 'price',
    minWidth: 90,
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
    minWidth: 150,
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
      {value.volumeUsd ? formatNumber(value.volumeUsd, 'USD') : '---'}
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
    minWidth: 150,
    accessor: 'marketcapUsd',
    Cell: ({value}) => <div className='market-cap'>{formatMarketCapProject(value)}</div>,
    sortable: true,
    sortMethod: (a, b) => simpleSort(parseInt(a, 10), parseInt(b, 10))
  }, {
    Header: 'Balance (USD/ETH)',
    id: 'balance',
    minWidth: 250,
    accessor: d => ({
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
    Header: 'ETH spent 30D',
    id: 'tx',
    accessor: d => d.ethSpent,
    Cell: ({value}) => <div>{`ETH ${formatNumber(value)}`}</div>,
    sortable: true,
    minWidth: 140,
    sortMethod: (a, b) => simpleSort(a, b)
  }, {
    Header: 'Dev activity 30D',
    id: 'github_activity',
    accessor: d => d.averageDevActivity,
    Cell: ({value}) => <div>{value ? parseFloat(value).toFixed(2) : '---'}</div>,
    sortable: true,
    minWidth: 140,
    sortMethod: (a, b) => simpleSort(a, b)
  }]

  return (
    <div className='page cashflow'>
      <FadeIn duration='0.7s' timingFunction='ease-in' as='div'>
        <div className='cashflow-head'>
          <h1>Projects: Cash Flow</h1>
          <p>
            brought to you by <a
              href='https://santiment.net'
              rel='noopener noreferrer'
              target='_blank'>Santiment</a>
            <br />
            NOTE: This app is in development.
            We give no guarantee data is correct as we are in active development.
            <br />
            <Icon color='red' name='question circle outline' />Automated data not available.&nbsp;
            <span className='cashflow-head-community-help'>
            Community help locating correct wallet is welcome!</span>
          </p>
        </div>
        <Panel>
          <div className='row'>
            <div className='datatables-info'>
              <label>
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
              </label>
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
