import fetch from 'isomorphic-unfetch'
import { WEBSITE_URL } from '../config'
import Layout from '../components/Layout'
import WalletList from '../components/WalletList'

const Index = ({projects, eth_price}) =>  {
  return (
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
    <div className="row">
        <div className="col-12">
            <div className="panel">
                <div className="sortable table-responsive">
                    <table id="projects" className="table table-condensed table-hover" cellspacing="0" width="100%">
                        <thead>
                        <tr>
                            <th>Project</th>
                            <th>Market Cap</th>
                            <th className="sorttable_numeric">Balance (USD/ETH)</th>
                            <th>Last outgoing TX</th>
                            <th>ETH sent</th>
                        </tr>
                        </thead>
                        <tbody className='whaletable'>
                          <WalletList projects={projects} eth_price={eth_price} />
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>
  </Layout>)
}

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
    projects: data.projects,
    eth_price: data.eth_price
  }
}

export default Index
