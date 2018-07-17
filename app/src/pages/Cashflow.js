import React from 'react'
import 'react-table/react-table.css'
import ProjectsTable from './Projects/ProjectsTable'
import withProjectsData from './Projects/withProjectsData'

export const Cashflow = ({
  Projects,
  onSearch,
  handleSetCategory,
  history,
  match,
  search,
  tableInfo,
  categories,
  allMarketSegments,
  preload
}) => {
  const { loading } = Projects
  const projects = filterProjectsByMarketSegment(Projects.projects, categories, allMarketSegments)

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
        <ProjectIcon name={value.name} ticker={value.ticker} /><br />
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
    width: 350,
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
    Header: 'ETH spent (30D)',
    maxWidth: 110,
    id: 'tx',
    accessor: d => d.ethSpent,
    Cell: ({value}) => <div className='overview-ethspent'>{`Ξ${formatNumber(value)}`}</div>,
    sortable: true,
    sortMethod: (a, b, isDesc) => (
      sortDate(a[0].last_outgoing, b[0].last_outgoing, isDesc)
    )
  }, {
    Header: 'Dev activity (30D)',
    id: 'github_activity',
    maxWidth: 110,
    accessor: d => d.averageDevActivity,
    Cell: ({value}) => <div className='overview-devactivity'>{value ? parseFloat(value).toFixed(2) : ''}</div>,
    sortable: true,
    sortMethod: (a, b) => simpleSort(a, b)
  }, {
    Header: 'Daily active addresses (30D)',
    id: 'daily_active_addresses',
    maxWidth: 110,
    accessor: d => d.averageDailyActiveAddresses,
    Cell: ({value}) => <div className='overview-activeaddresses'>{value ? formatNumber(value) : ''}</div>,
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
      <div className='cashflow-head'>
        <h1>Cash Flow</h1>
        <p>
          brought to you by <a
            href='https://santiment.net'
            rel='noopener noreferrer'
            target='_blank'>Santiment</a>
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
    tableInfo: state.projects.tableInfo,
    categories: state.projects.categories
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
    },
    handleSetCategory: (event) => {
      dispatch({
        type: 'SET_CATEGORY',
        payload: {
          category: event.target
        }
      })
    }
  }
}

const mapDataToProps = ({allProjects}) => {
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
  graphql(allMarketSegments, {
    name: 'allMarketSegments',
    props: ({allMarketSegments: {allMarketSegments}}) => (
      { allMarketSegments: allMarketSegments ? JSON.parse(allMarketSegments) : {} }
    )
  }),
  pure
)

export default withProjectsData({ type: 'erc20' })(Cashflow)
