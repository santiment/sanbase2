import React from 'react'
import ProjectsMobile from './Projects/ProjectsMobile'
import withProjectsDataMobile from './Projects/withProjectsDataMobile'

const CurrenciesMobile = props => (
  <ProjectsMobile type={'currency'} {...props} />
)

export default withProjectsDataMobile({ type: 'currency' })(CurrenciesMobile)
