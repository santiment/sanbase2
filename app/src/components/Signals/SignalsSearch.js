import React from 'react'
import { push } from 'react-router-redux'
import { connect } from 'react-redux'
import { graphql } from 'react-apollo'
import { compose } from 'recompose'
import { allProjectsForSearchGQL } from './../../pages/Projects/allProjectsGQL'
import { getAll } from './../../pages/Projects/projectSelectors'
import * as actions from './../../actions/types'
import Search from '../Search/Search'
import './SearchSuggestions.css'

const SearchContainer = ({
  projects = [],
  isFocused,
  resetFocus,
  goto,
  slug
}) => (
  <div className='signals-input-wrapper'>
    <Search
      onSelectProject={cmcId => goto(cmcId)}
      focus={isFocused}
      resetFocus={resetFocus}
      projects={projects}
      value={slug}
      className='signals-input'
      hasToResetAfterSelect={false}
    />
  </div>
)

const mapDataToProps = ({ allProjects }) => ({
  projects: getAll(allProjects.allProjects)
})

const mapStateToProps = ({ rootUi }) => ({
  isFocused: rootUi.isSearchInputFocused
})

const mapDispatchToProps = dispatch => ({
  resetFocus: () => dispatch({ type: actions.APP_TOGGLE_SEARCH_FOCUS }),
  goto: cmcId => dispatch(push(`/signals/${cmcId}`))
})

const enhance = compose(
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
  graphql(allProjectsForSearchGQL, {
    name: 'allProjects',
    props: mapDataToProps,
    options: () => ({
      context: { isRetriable: true }
    })
  })
)

export default enhance(SearchContainer)
