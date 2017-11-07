import Wallet from './Wallet'

const WalletList = ({projects, eth_price}) => {
  if (projects.length == 0) {
    return (<div>No Projects</div>);
  }

  return projects.map((project) => {
    var market_cap_usd;
    if(project.market_cap_usd !== null)
    {
      market_cap_usd = "$" + project.market_cap_usd.toLocaleString('en-US', {maximumFractionDigits: 0});
    }
    else
    {
      market_cap_usd = "No data";
    }

    var logo_url = project.logo_url !== null ? project.logo_url.toString().toLowerCase() : "";

    return(
    <tr>
        <td><img src={"/static/cashflow/img/"+logo_url} />{project.name} ({project.ticker})</td>
        <td className="marketcap">{market_cap_usd}</td>
        <td className="address-link" data-order={project.balance}>
          {project.wallets.map((wallet) => {
            return (<Wallet wallet={wallet} eth_price={eth_price} />)
          })}
        </td>
        <td>
          {project.wallets.map((wallet) => {
            return (
              <div>
                {wallet.last_outgoing}
              </div>
            )
          })}
        </td>
        <td>
          {project.wallets.map((wallet) => {
            var tx_out = wallet.tx_out !== null ? wallet.tx_out : 0;
            return(
            <div>
              {tx_out.toLocaleString('en-US')}
            </div>
            )
          })}
        </td>
    </tr>)
  })
}


export default WalletList
