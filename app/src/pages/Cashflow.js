import React from 'react'
import ReactTable from 'react-table'
import classnames from 'classnames'
import throttle from 'lodash.throttle'
import { graphql } from 'react-apollo'
import { connect } from 'react-redux'
import { withRouter, Link } from 'react-router-dom'
import { Helmet } from 'react-helmet'
import { Icon, Popup, Message, Loader } from 'semantic-ui-react'
import { compose, pure } from 'recompose'
import 'react-table/react-table.css'
import { FadeIn } from 'animate-components'
import Sticky from 'react-stickynode'
import { formatNumber, millify } from 'utils/formatting'
import { getOrigin } from 'utils/utils'
import ProjectIcon from './../components/ProjectIcon'
import { simpleSort } from 'utils/sortMethods'
import Panel from './../components/Panel'
import { allErc20ProjectsGQL } from './Projects/allProjectsGQL'
import PercentChanges from './../components/PercentChanges'
import './Cashflow.css'

export const refetchThrottled = data => {
  throttle(data => data.refetch(), 1000)
}

export const Tips = () =>
  <div style={{ textAlign: 'center' }}>
    <em>Tip: Hold shift when sorting to multi-sort!</em>
  </div>

export const CustomThComponent = ({ toggleSort, className, children, ...rest }) => (
  <div
    className={classnames('rt-th', className)}
    onClick={e => (
      toggleSort && toggleSort(e)
    )}
    role='columnheader'
    tabIndex='-1'
    {...rest}
  >
    {((Array.isArray(children) ? children[0] : {}).props || {}).children === 'P/B'
      ? <Popup
        trigger={<div>{children}</div>}
        content='Ratio between the market cap and the current crypto balance.
          Companies with low P/B ratio might be undervalued.'
        inverted
        position='top left'
      />
      : children}
  </div>
)

export const CustomHeadComponent = ({ children, className, ...rest }) => (
  <Sticky enabled >
    <div className={classnames('rt-thead', className)} {...rest}>
      {children}
    </div>
  </Sticky>
)

export const formatBalance = ({ethBalance, usdBalance, project, ticker}) => (
  <div className='wallet'>
    <div className='usd first'>
      {usdBalance
        ? `$${millify(usdBalance, 2)}`
        : '---'}
    </div>
    <div className='eth'>
      {parseFloat(ethBalance) === 0 &&
        <Popup
          inverted
          trigger={<div style={{display: 'inline-block'}}>{
            <a
              target='_blank'
              rel='noopener noreferrer'
              className='findwallet'
              href={`https://santiment.typeform.com/to/bT0Dgu?project=${project}&ticker=${ticker}`}>
              <Icon color='red' name='question circle outline' />
            </a>}
          </div>}
          content='Know this project wallet? Click the ? to send wallet info'
          position='top center'
        />
      }
      {ethBalance
        ? `Ξ${millify(ethBalance, 2)}`
        : '---'}
    </div>
  </div>
)

export const formatMarketCapProject = marketcapUsd => {
  if (marketcapUsd !== null) {
    return `$${millify(marketcapUsd, 2)}`
  } else {
    return 'No data'
  }
}

export const getFilter = search => {
  if (search) {
    return [{
      id: 'project',
      value: search
    }]
  }
  return []
}

export const PriceColumn = {
  Header: 'Price',
  id: 'price',
  maxWidth: 100,
  accessor: d => ({
    priceUsd: d.priceUsd,
    change24h: d.percentChange24h
  }),
  Cell: ({value: {priceUsd, change24h}}) => <div className='overview-price'>
    {priceUsd ? formatNumber(priceUsd, { currency: 'USD' }) : 'No data'}
    &nbsp;
    {<PercentChanges changes={change24h} />}
  </div>,
  sortable: true,
  sortMethod: (a, b) => simpleSort(parseFloat(a.priceUsd || 0), parseFloat(b.priceUsd || 0))
}

export const VolumeColumn = {
  Header: 'Volume',
  id: 'volume',
  maxWidth: 100,
  accessor: d => ({
    volumeUsd: d.volumeUsd,
    change24h: d.volumeChange24h
  }),
  Cell: ({value: {volumeUsd, change24h}}) => <div className='overview-volume'>
    {volumeUsd
      ? `$${millify(volumeUsd, 2)}`
      : 'No data'}
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
}

export const MarketCapColumn = {
  Header: 'Market Cap',
  id: 'marketcapUsd',
  maxWidth: 130,
  accessor: 'marketcapUsd',
  Cell: ({value}) => <div className='overview-marketcap'>{formatMarketCapProject(value)}</div>,
  sortable: true,
  sortMethod: (a, b) => simpleSort(+a, +b)
}

export const Cashflow = ({
  Projects = {
    projects: [],
    filteredProjects: [],
    loading: true,
    isError: false,
    isEmpty: true,
    refetch: null
  },
  onSearch,
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
    accessor: d => ({
      name: d.name,
      ticker: d.ticker
    }),
    Cell: ({value}) => (
      <div className='overview-ticker' >
        <ProjectIcon name={value.name} /><br />
        <span className='ticker'>{value.ticker}</span>
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
    Header: 'Balance (USD/ETH)',
    maxWidth: 110,
    id: 'balance',
    accessor: d => ({
      project: d.name,
      ticker: d.ticker,
      ethBalance: d.ethBalance,
      usdBalance: d.usdBalance
    }),
    Cell: ({value}) => <div className='overview-balance'>{formatBalance(value)}</div>,
    sortable: true,
    sortMethod: (a, b) =>
      simpleSort(
        parseFloat(a.ethBalance || 0),
        parseFloat(b.ethBalance || 0)
      )
  }, {
    Header: 'P/B',
    id: 'pbr',
    maxWidth: 100,
    accessor: 'priceToBookRatio',
    Cell: ({value}) => <div className='overview-pb'>{value &&
      ((value) => {
        if (value > 1000000000000) {
          return '∞'
        }
        return millify(value, 3)
      })(value)
    }</div>,
    sortable: true,
    sortMethod: (a, b) => {
      return simpleSort(
        parseFloat(a || 0),
        parseFloat(b || 0)
      )
    }
  }, {
    Header: 'ETH spent (30D)',
    maxWidth: 110,
    id: 'tx',
    accessor: d => d.ethSpent,
    Cell: ({value}) => <div className='overview-ethspent'>{`Ξ${formatNumber(value)}`}</div>,
    sortable: true,
    sortMethod: (a, b) => simpleSort(a, b)
  }, {
    Header: 'Dev activity (30D)',
    id: 'github_activity',
    maxWidth: 110,
    accessor: d => d.averageDevActivity,
    Cell: ({value}) => <div className='overview-devactivity'>{value ? parseFloat(value).toFixed(2) : ''}</div>,
    sortable: true,
    sortMethod: (a, b) => simpleSort(a, b)
  }, {
    Header: 'Signals',
    id: 'signals',
    minWidth: 64,
    accessor: d => ({
      warning: d.signals && d.signals.length > 0,
      description: d.signals[0] && d.signals[0].description
    }),
    Cell: ({value: {warning, description}}) => <div className='cell-signals'>
      {warning &&
        <Popup basic
          position='right center'
          hideOnScroll
          wide
          inverted
          trigger={
            <div style={{width: '100%', height: '100%'}}>
              <Icon color='orange' fitted name='warning sign' />
            </div>}
          on='hover'>
          {description}
        </Popup>}
    </div>,
    sortable: true,
    sortMethod: (a, b) => simpleSort(a.warning, b.warning)
  }]

  return (
    <div className='page cashflow'>
      <Helmet>
        <title>SANbase: ERC20 Projects</title>
        <link rel='canonical' href={`${getOrigin()}/projects`} />
      </Helmet>
      <FadeIn duration='0.3s' timingFunction='ease-in' as='div'>
        <div className='cashflow-head'>
          <div className='cashflow-title'>
            <h1>ERC20 Projects</h1>
            <span><Link to={'/projects/ethereum'}>More data about Ethereum</Link></span>
          </div>
          <p>
            <Icon color='red' name='question circle outline' />
            Automated data not available.&nbsp;
            <span>Community help locating correct wallets is welcome!</span>
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
  const projects = allProjects.allErc20Projects

  const isEmpty = projects && projects.length === 0
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
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
  withRouter,
  graphql(allErc20ProjectsGQL, {
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

export default enhance(Cashflow)
