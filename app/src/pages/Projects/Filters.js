import React from 'react'
import { Button } from 'semantic-ui-react'
import './Filters.css'

export const DEFAULT_SORT_BY = 'marketcap'
export const DEFAULT_FILTER_BY = {}

const FilterDivider = ({children}) => (
  <div className='cashflow-mobile-filters__divider'>
    {children}
  </div>
)

const Filters = ({
  onFilterChanged,
  filterBy = DEFAULT_FILTER_BY,
  sortBy = DEFAULT_SORT_BY,
  changeFilter,
  changeSort
}) => {
  return (
    <div className='cashflow-mobile-filters-overlay'>
      <div className='cashflow-mobile-filters'>
        <div className='cashflow-mobile-filters__header'>
          <Button
            basic
            onClick={() => {
              changeSort(DEFAULT_SORT_BY)
              changeFilter(DEFAULT_FILTER_BY)
            }}>
            Clear
          </Button>
          <h4>Filters</h4>
          <Button
            onClick={() => onFilterChanged({
              sortBy,
              filterBy
            })}
            color='green'>
            Done
          </Button>
        </div>
        <FilterDivider>
          Sort by
        </FilterDivider>
        <div className='cashflow-mobile-filters__item'>
          <Button
            color={sortBy === 'marketcap' ? 'blue' : undefined}
            onClick={() => changeSort('marketcap')}>
            Marketcap
          </Button>
          <Button
            color={sortBy === 'github_activity' ? 'blue' : undefined}
            onClick={() => changeSort('github_activity')}>
            Github Activity
          </Button>
        </div>
        <FilterDivider>
          Filter by
        </FilterDivider>
        <div className='cashflow-mobile-filters__item'>
          <Button
            basic
            color={filterBy['signals'] ? 'blue' : undefined}
            onClick={() => changeFilter({...filterBy, signals: !filterBy['signals']})}>
            Any signal was detected
          </Button>
          <Button
            basic
            color={filterBy['spent_eth_30d'] ? 'blue' : undefined}
            onClick={() => changeFilter({...filterBy, spent_eth_30d: !filterBy['spent_eth_30d']})}>
            Spent eth in the last 30d
          </Button>
        </div>
      </div>
    </div>
  )
}

export default Filters
