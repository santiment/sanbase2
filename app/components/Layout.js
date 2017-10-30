import Link from 'next/link'
import Head from 'next/head'
import SideMenu from './side-menu';
import TableProjects from './table-projects';

export default (props) => (
    <div>
        <Head>
            <link href="/static/cashflow/css/style_dapp_mvp1.css" rel="stylesheet" />
            <link href="https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0-alpha.6/css/bootstrap.min.css" rel="stylesheet" crossorigin="anonymous"/>
            <link href="https://use.fontawesome.com/6f993f4769.css" media="all" rel="stylesheet" />
        </Head>
        <div className="nav-side-menu">
            <div className="brand">
                <img src="/static/logo_sanbase.png" width="115" height="22"/>
            </div>
            <SideMenu/>
        </div>
        <div className="container" id="main">
            <div className="row">
                <div className="col-lg-5">
                    <h1>Cash Flow</h1>
                </div>
                <div className="col-lg-7 community-actions">
                    <span className="legal">
                        brought to you by
                        <a href="https://santiment.net">Santiment</a>
                        <br />
                        NOTE: This app is a prototype. We give no guarantee data is correct as we are in active development
                    </span>
                </div>
            </div>
            <TableProjects/>
        </div>
    </div>
)
