import fetch from 'isomorphic-unfetch'
import { WEBSITE_URL } from '../config'
import Layout from '../components/main-layout'
import ProjectsTable from '../components/projects-table'

const Index = (props) => (
<Layout>
  <div className="row">
      <div className="col-lg-5">
          <h1>Cash Flow</h1>
      </div>
      <div className="col-lg-7 community-actions">
           <span className="legal">brought to you by <a href="https://santiment.net" target="_blank">Santiment</a>
           <br />
           NOTE: This app is a prototype. We give no guarantee data is correct as we are in active development.</span>
      </div>
  </div>
  <ProjectsTable data={ props.data }/>
</Layout>
)

Index.getInitialProps = async function() {
  //const res = await fetch(WEBSITE_URL + '/api/cashflow')
  //const data = await res.json()

  const data = {
    projects: [
      {
        market_cap_usd: 1,
        balance: 45,
        name: 'EOS',
        ticker: 'EOS',
        logo_url: 'eos.png',
        wallets: [
          {
            last_outgoing: null,
            balance: null,
            tx_out: null
          }
        ]
      }
    ],
    eth_price: 2
  };

  return {
    data: data
  }
}

export default Index
