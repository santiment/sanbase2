import React from 'react'
import { withApollo } from 'react-apollo'
import { compose, pure } from 'recompose'
import {
  allProjectsGQL,
  allErc20ProjectsGQL,
  currenciesGQL
} from './../Projects/allProjectsGQL'

const mapDataToProps = (type, result) => {
  const loading = result.loading
  const isError = !!result.error
  const errorMessage = result.error ? result.error.message : ''
  const assets = result.data[pickProjectsType(type).projects] || []

  const isEmpty = assets && assets.length === 0
  return {
    loading,
    isEmpty,
    isError,
    assets,
    errorMessage,
    refetch: Assets.refetch
  }
}

const pickProjectsType = type => {
  switch (type) {
    case 'all':
      return {
        projects: 'allProjects',
        gql: allProjectsGQL
      }
    case 'currency':
      return {
        projects: 'allCurrencyProjects',
        gql: currenciesGQL
      }
    case 'erc20':
      return {
        projects: 'allErc20Projects',
        gql: allErc20ProjectsGQL
      }
    default:
      return {
        projects: 'allProjects',
        gql: allProjectsGQL
      }
  }
}

const enhance = compose(withApollo, pure)

class Assets extends React.Component {
  state = {
    Assets: {
      loading: false,
      isEmpty: true,
      isError: false,
      assets: [],
      errorMessage: null,
      refetch: null
    }
  }

  componentDidMount () {
    this.props.client
      .query({
        options: {
          fetchPolicy: 'network-only'
        },
        query: pickProjectsType(this.props.type).gql
      })
      .then(res => {
        this.setState({ Assets: mapDataToProps(this.props.type, res) })
      })
      .catch(err => {
        console.log('error', err)
      })
  }

  render () {
    const { children, render, type = 'all' } = this.props
    const { Assets = {} } = this.state
    const props = { type, ...Assets }

    if (typeof children === 'function') return children(props)

    return render(props)
  }
}

export default enhance(Assets)
