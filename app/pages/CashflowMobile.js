import React from 'react'
import ProjectsMobile from './Projects/ProjectsMobile'
import withProjectsDataMobile from './Projects/withProjectsDataMobile'

const CashflowMobile = props => <ProjectsMobile type={'erc20'} {...props} />

export default withProjectsDataMobile({ type: 'erc20' })(CashflowMobile)
