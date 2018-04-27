import React, { Component } from 'react'
import { SlideDown } from 'animate-components'
import { Loader, Message, Button } from 'semantic-ui-react'
import { List, AutoSizer, CellMeasurer, CellMeasurerCache } from 'react-virtualized'

import Search from './../../components/Search'
import ProjectCard from './ProjectCard'
import FloatingButton from './FloatingButton'
import Filters, {
  DEFAULT_SORT_BY,
  DEFAULT_FILTER_BY
} from './Filters'
import './ProjectsMobile.css'

export default class ProjectsMobile extends Component {
  constructor (props) {
    super(props)
    this.state = {
      expandedCards: {}
    }
  }

  /* eslint-disable no-undef */
  toggleExpandCard = (index) => () => {
    this.setState({expandedCards: {...this.state.expandedCards, [index]: !this.state.expandedCards[index]}},
      this.updateRowHeight(index)
    )
  }

  cache = new CellMeasurerCache({
    defaultHeight: 248,
    fixedWidth: true
  })

  updateRowHeight = (index) => () => {
    this.cache.clear(index)
    this.projectsList.recomputeRowHeights(index)
  }

  rowRenderer = ({
    key,
    index,
    isScrolling,
    isVisible,
    style,
    parent
  }) => {
    const project = this.props.Projects.filteredProjects[index]
    const {type = 'erc20', history} = this.props

    return (
      <CellMeasurer
        cache={this.cache}
        columnIndex={0}
        key={key}
        rowIndex={index}
        parent={parent}>
        {({measure}) => (
          <div
            key={key}
            style={style}
          >
            <ProjectCard
              type={type}
              history={history}
              onLoad={measure}
              toggleExpandCard={this.toggleExpandCard(index)}
              isExpanded={this.state.expandedCards[index]}
              {...project}
            />
          </div>
        )}
      </CellMeasurer>
    )
  }
  /* eslint-enable no-undef */

  render () {
    const {
      Projects = {
        projects: [],
        filteredProjects: [],
        loading: true,
        isError: false,
        isEmpty: true
      },
      isSearchFocused = false,
      focusSearch,
      filterByName,
      isFilterOpened = false,
      toggleFilter,
      changeFilter,
      changeSort,
      filterBy = DEFAULT_FILTER_BY,
      sortBy = DEFAULT_SORT_BY
    } = this.props
    const { projects } = Projects

    if (Projects.loading) {
      return (<Loader active size='large' />)
    }
    if (Projects.isError) {
      return (
        <div style={{display: 'flex', alignItems: 'center', justifyContent: 'center', height: '80vh'}}>
          <Message warning>
            <Message.Header>Something going wrong on our server.</Message.Header>
            <p>Please try again later.</p>
          </Message>
        </div>
      )
    }

    return (
      <div className='cashflow-mobile'>
        {isSearchFocused &&
          <SlideDown duration='0.3s' timingFunction='ease-out' as='div'>
            <div className='cashflow-mobile-search'>
              <Search
                focus={focusSearch}
                onSelectProject={ticker => filterByName(ticker.toLowerCase())}
                projects={projects} />
              <Button
                basic
                onClick={() => toggleFilter(!isFilterOpened)}
                className='cashflow-mobile-search__filter'>
                Filter
              </Button>
            </div>
          </SlideDown>}
        <AutoSizer>
          {({ height, width }) => (
            <List
              className='List'
              ref={(ref) => { this.projectsList = ref }}
              width={width}
              height={height}
              rowCount={Projects.filteredProjects.length}
              overscanRowCount={5}
              deferredMeasurementCache={this.cache}
              rowHeight={this.cache.rowHeight}
              rowRenderer={this.rowRenderer}
            />
          )}
        </AutoSizer>
        {isFilterOpened &&
          <Filters
            filterBy={filterBy}
            sortBy={sortBy}
            changeFilter={changeFilter}
            changeSort={changeSort}
            onFilterChanged={filters => {
              toggleFilter(!isFilterOpened)
            }} />
        }
        <FloatingButton handleSearchClick={() => {
          filterByName(null)
          focusSearch(!isSearchFocused)
        }} />
      </div>
    )
  }
}
