import React, { Component } from 'react';

const wei_to_eth = 1000000000000000000.0;

class ProjectsTable extends Component {
  constructor(props){
    super(props)
    this.projects = this.props.data.projects
    this.ethPrice = this.props.data.eth_price
  }

  formatTxOutWallet(wallet, index){
    const txOut = wallet.tx_out !== null ? wallet.tx_out : 0;

    return (
      <div key={ index }>
        { txOut.toLocaleString('en-US') }
      </div>
    )
  }

  formatLastOutgoingWallet(wallet, index){
    const lastOutgoing = wallet.last_outgoing !== null ? wallet.last_outgoing : 'No recent transfers';

    return (
      <div key={ index }>
        { lastOutgoing }
      </div>
    )
  }

  formatBalanceWallet(wallet, index){
    const balance = wallet.balance !== null ? wallet.balance / wei_to_eth : 0;

    return (
      <div className="wallet" key={ index }>
        <div className="usd first">${(balance * this.ethPrice).toLocaleString('en-US', {maximumFractionDigits: 0})}</div>
        <div className="eth">
          <a className="address" href={ "https://etherscan.io/address/" + wallet.address } target="_blank">Ξ{ balance.toLocaleString('en-US') }
            <i className="fa fa-external-link"></i>
          </a>
        </div>
      </div>
    )
  }

  formatMarketCapProject(project){
    let marketCapUsd;

    if(project.market_cap_usd !== null){
      return marketCapUsd = "$" + project.market_cap_usd.toLocaleString('en-US', { maximumFractionDigits: 0 });
    } else {
      return marketCapUsd = "No data";
    }
  }

  render() {
    return (
      <div className="row">
        <div className="col-12">
          <div className="panel">
            <div className="sortable table-responsive">
              <table id="projects" className="table table-condensed table-hover" cellSpacing="0" width="100%">
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
                {
                  this.projects.map((project, index) => {
                    var logoUrl = project.logo_url !== null ? project.logo_url.toString().toLowerCase() : "";

                    return (
                      <tr key={ index }>
                        <td><img src={ "/static/cashflow/img/" + logoUrl } />{ project.name } ({ project.ticker })</td>
                        <td className="marketcap">{ this.formatMarketCapProject(project) }</td>
                        <td className="address-link" data-order={ project.balance }>
                        {
                          project.wallets.map(this.formatBalanceWallet, this)
                        }
                        </td>
                        <td>
                        {
                          project.wallets.map(this.formatLastOutgoingWallet)
                        }
                        </td>
                        <td>
                        {
                          project.wallets.map(this.formatTxOutWallet)
                        }
                        </td>
                      </tr>
                    )
                  })
                }
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    )
  }
}

export default ProjectsTable
