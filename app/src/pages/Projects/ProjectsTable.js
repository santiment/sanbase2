import React from 'react'
import ReactTable from 'react-table'
import classnames from 'classnames'
import throttle from 'lodash.throttle'
import { Helmet } from 'react-helmet'
import { Icon, Popup, Message, Loader } from 'semantic-ui-react'
import 'react-table/react-table.css'
import { FadeIn } from 'animate-components'
import Sticky from 'react-stickynode'
import { formatNumber, millify } from '../../utils/formatting'
import { getOrigin, filterProjectsByMarketSegment } from '../../utils/utils'
import { simpleSort } from '../../utils/sortMethods'
import ProjectIcon from '../../components/ProjectIcon'
import Panel from '../../components/Panel'
import PercentChanges from '../../components/PercentChanges'
import ProjectsNavigation from '../../components/ProjectsNavigation'
import HelpPopup from '../../components/HelpPopup/HelpPopup'
import HelpPopupProjectsContent from '../../components/HelpPopup/HelpPopupProjectsContent'
import './ProjectsTable.css'

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

export const filterColumnsByTableSection = (tableSection, columns) => {
  if (tableSection === 'currencies') {
    return columns.filter(column =>
      column.id !== 'eth_spent' &&
      column.id !== 'daily_active_addresses' &&
      column.id !== 'signals')
  }
  return columns
}

const ProjectsTable = ({
  Projects = {
    projects: [],
    filteredProjects: [],
    loading: true,
    isError: false,
    isEmpty: true,
    refetch: null
  },
  onSearch,
  handleSetCategory,
  history,
  match,
  search,
  tableInfo,
  categories,
  allMarketSegments,
  preload,
  user
}) => {
  const { loading } = Projects
  const projects = filterProjectsByMarketSegment(Projects.projects, categories, allMarketSegments)
  const currentTableSection = match.path.split('/')[1] // currencies or projects ...
  const refetchThrottled = data => {
    throttle(data => data.refetch(), 1000)
  }
  const formatMarketCapProject = marketcapUsd => {
    if (marketcapUsd !== null) {
      return `$${millify(marketcapUsd, 2)}`
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

  if (Projects.isError && Projects.errorMessage !== 'Network error: Failed to fetch') {
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
    maxWidth: 100,
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
      priceUsd: d.priceUsd
    }),
    Cell: ({value: {priceUsd, change24h}}) => <div className='overview-price'>
      {priceUsd ? formatNumber(priceUsd, { currency: 'USD' }) : 'No data'}
    </div>,
    sortable: true,
    sortMethod: (a, b) => simpleSort(parseFloat(a.priceUsd || 0), parseFloat(b.priceUsd || 0))
  }, {
    Header: 'Price +/-',
    id: 'price_change',
    maxWidth: 100,
    accessor: d => ({
      change24h: d.percentChange24h
    }),
    Cell: ({value: {change24h}}) => <div className='overview-price'>
      {change24h
        ? <PercentChanges changes={change24h} />
        : 'No data'}
    </div>,
    sortable: true,
    sortMethod: (a, b) => simpleSort(parseFloat(a.change24h || 0), parseFloat(b.change24h || 0))
  }, {
    Header: 'Volume',
    id: 'volume',
    maxWidth: 100,
    accessor: d => ({
      volumeUsd: d.volumeUsd
    }),
    Cell: ({value: {volumeUsd}}) => <div className='overview-volume'>
      {volumeUsd
        ? `$${millify(volumeUsd, 2)}`
        : 'No data'}
    </div>,
    sortable: true,
    sortMethod: (a, b) =>
      simpleSort(
        parseFloat(a.volumeUsd || 0),
        parseFloat(b.volumeUsd || 0)
      )
  }, {
    Header: 'Volume +/-',
    id: 'volume_change_24h',
    maxWidth: 100,
    accessor: d => ({
      change24h: d.volumeChange24h
    }),
    Cell: ({value: {change24h}}) => <div className='overview-volume'>
      {change24h
        ? <PercentChanges changes={change24h} />
        : 'No data'}
    </div>,
    sortable: true,
    sortMethod: (a, b) =>
      simpleSort(
        parseFloat(a.change24h || 0),
        parseFloat(b.change24h || 0)
      )
  }, {
    Header: 'Market Cap',
    id: 'marketcapUsd',
    maxWidth: 130,
    accessor: 'marketcapUsd',
    Cell: ({value}) => <div className='overview-marketcap'>{formatMarketCapProject(value)}</div>,
    sortable: true,
    sortMethod: (a, b) => simpleSort(+a, +b)
  },
  {
    Header: 'ETH spent (30D)',
    maxWidth: 110,
    id: 'eth_spent',
    accessor: d => d.ethSpent,
    Cell: ({value}) => <div className='overview-ethspent'>{`Ξ${millify(value, 2)}`}</div>,
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
    <div className='page projects-table'>
      <Helmet>
        <title>SANbase: ERC20 Projects</title>
        <link rel='canonical' href={`${getOrigin()}/projects`} />
      </Helmet>
      <FadeIn duration='0.3s' timingFunction='ease-in' as='div'>
        <div className='page-head page-head-projects'>
          <div className='page-head-projects__left'>
            <h1>Markets</h1>
            <HelpPopup>
              <HelpPopupProjectsContent />
            </HelpPopup>
          </div>
          <div>
            <ProjectsNavigation
              path={match.path}
              categories={categories}
              handleSetCategory={handleSetCategory}
              allMarketSegments={allMarketSegments}
              user={user}
              />
          </div>
        </div>
        <Panel>
          <div className='row projects-search-row'>
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
            columns={filterColumnsByTableSection(currentTableSection, columns)}
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
    </div>
  )
}

export default ProjectsTable
