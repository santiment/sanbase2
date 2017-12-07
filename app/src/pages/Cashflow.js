import React from 'react'
import { Link } from 'react-router-dom'
import ReactTable from 'react-table'
import { connect } from 'react-redux'
import {
  compose,
  pure,
  lifecycle
} from 'recompose'
import 'react-table/react-table.css'
import moment from 'moment'
import { formatNumber } from '../utils/formatting'
import ProjectIcon from './../components/ProjectIcon'
import './Cashflow.css'

const formatDate = date => moment(date).format('YYYY-MM-DD')

const formatLastOutgoingWallet = wallets => {
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

const formatTxOutWallet = wallets => {
  return wallets.map((wallet, index) => {
    const txOut = wallet.tx_out || 0
    return (
      <div key={index}>
        {txOut.toLocaleString('en-US')}
      </div>
    )
  })
}

const formatBalanceWallet = ({wallets, ethPrice}) => {
  return wallets.map((wallet, index) => {
    const balance = wallet.balance || 0
    return (
      <div className='wallet' key={index}>
        <div className='usd first'>{formatNumber((balance * ethPrice), 'USD')}</div>
        <div className='eth'>
          <a className='address' href={'https://etherscan.io/address/' + wallet.address} target='_blank'>Ξ{ balance.toLocaleString('en-US') }
            <i className='fa fa-external-link' />
          </a>
        </div>
      </div>
    )
  })
}

const formatMarketCapProject = cap => {
  if (cap !== null) {
    return formatNumber(cap, 'USD')
  } else {
    return 'No data'
  }
}

const getFilter = search => {
  if (search !== null) {
    return [{
      id: 'project',
      value: search
    }]
  } else {
    return []
  }
}

const columns = [{
  Header: 'Project',
  id: 'project',
  filterable: true,
  sortable: true,
  width: 350,
  accessor: d => ({
    name: d.name,
    ticker: d.ticker
  }),
  Cell: ({value}) => (
    <div>
      <ProjectIcon name={value.name} /> {value.name} ({value.ticker})
    </div>
  ),
  filterMethod: (filter, row) => {
    return row[filter.id].name.toLowerCase().indexOf(filter.value) !== -1 ||
      row[filter.id].ticker.toLowerCase().indexOf(filter.value) !== -1
  },
  Filter: ({filter, onChange}) => {}
}, {
  Header: 'Market Cap',
  id: 'market_cap_usd',
  sortable: true,
  minWidth: 150,
  accessor: 'market_cap_usd',
  Cell: props => <span className='market-cap'>{formatMarketCapProject(props.value)}</span>, // Custom cell components!
  sortMethod: (a, b) => {
    const _a = parseInt(a, 10)
    const _b = parseInt(b, 10)
    if (_a === _b) {
      return 0
    }
    return _a > _b ? 1 : -1
  }
}, {
  Header: 'Balance (USD/ETH)',
  id: 'balance',
  minWidth: 250,
  accessor: d => ({
    ethPrice: d.ethPrice,
    wallets: d.wallets
  }),
  Cell: props => <div>{formatBalanceWallet(props.value)}</div>
}, {
  Header: 'Last outgoing TX',
  id: 'tx',
  accessor: d => d.wallets,
  Cell: props => <div>{formatLastOutgoingWallet(props.value)}</div>
}, {
  Header: 'ETH sent',
  id: 'sent',
  accessor: d => d.wallets,
  Cell: props => <div>{formatTxOutWallet(props.value)}</div>
}]

export const Cashflow = ({
  projects,
  loading,
  onSearch,
  search,
  tableInfo
}) => (
  <div className='page cashflow'>
    <div className='cashflow-head'>
      <h1>Cash Flow</h1>
      <p>
        brought to you by <a href='https://santiment.net' target='_blank'>Santiment</a>
        <br />
        NOTE: This app is a prototype.
        We give no guarantee data is correct as we are in active development.
      </p>
    </div>
    <div className='panel'>
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
        defaultPageSize={projects.items ? projects.items.length : 32}
        sortable={false}
        resizable
        defaultSorted={[
          {
            id: 'market_cap_usd',
            desc: true
          }
        ]}
        className='-highlight'
        data={projects}
        columns={columns}
        filtered={getFilter(search)}
      />
    </div>
  </div>
)

const mapStateToProps = state => {
  return {
    projects: state.projects.items,
    loading: state.projects.loading,
    search: state.projects.search,
    tableInfo: state.projects.tableInfo
  }
}

const mapDispatchToProps = dispatch => {
  return {
    retrieveProjects: () => {
      dispatch({
        types: ['LOADING_PROJECTS', 'SUCCESS_PROJECTS', 'FAILED_PROJECTS'],
        payload: {
          client: 'sanbaseClient',
          request: {
            url: `/cashflow`
          }
        }
      })
    },
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

const enhance = compose(
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
  lifecycle({
    componentDidMount () {
      this.props.retrieveProjects()
    }
  }),
  pure
)

export default enhance(Cashflow)
