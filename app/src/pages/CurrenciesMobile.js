import React from 'react'
import ProjectsMobile from './Projects/ProjectsMobile'
import withProjectsData from './Projects/withProjectsData'

const CurrenciesMobile = props => <ProjectsMobile type={'currency'} {...props} />

export default withProjectsData({type: 'currency'})(CurrenciesMobile)
